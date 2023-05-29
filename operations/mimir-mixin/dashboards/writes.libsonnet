local utils = import 'mixin-utils/utils.libsonnet';
local filename = 'mimir-writes.json';

(import 'dashboard-utils.libsonnet') +
(import 'dashboard-queries.libsonnet') {
  [filename]:
    ($.dashboard('Writes') + { uid: std.md5(filename) })
    .addClusterSelectorTemplates()
    .addRowIf(
      $._config.show_dashboard_descriptions.writes,
      ($.row('Writes dashboard description') { height: '125px', showTitle: false })
      .addPanel(
        $.textPanel('', |||
          <p>
            This dashboard shows various health metrics for the write path.
            It is broken into sections for each service on the write path,
            and organized by the order in which the write request flows.
            <br/>
            Incoming metrics data travels from the gateway → distributor → ingester.
            <br/>
            For each service, there are 3 panels showing
            (1) requests per second to that service,
            (2) average, median, and p99 latency of requests to that service, and
            (3) p99 latency of requests to each instance of that service.
          </p>
          <p>
            It also includes metrics for the key-value (KV) stores used to manage
            the high-availability tracker and the ingesters.
          </p>
        |||),
      )
    ).addRow(
      ($.row('Headlines') +
       {
         height: '100px',
         showTitle: false,
       })
      .addPanel(
        $.panel('Samples / sec') +
        $.statPanel(
          $.queries.distributor.samplesPerSecond,
          format='short'
        )
      )
      .addPanel(
        local title = 'Exemplars / sec';
        $.panel(title) +
        $.statPanel(
          $.queries.distributor.exemplarsPerSecond,
          format='short'
        ) +
        $.panelDescription(
          title,
          |||
            The total number of received exemplars by the distributors, excluding rejected and deduped exemplars, but not necessarily ingested by the ingesters.
          |||
        )
      )
      .addPanel(
        local title = 'In-memory series';
        $.panel(title) +
        $.statPanel(|||
          sum(cortex_ingester_memory_series{%(ingester)s}
          / on(%(group_by_cluster)s) group_left
          max by (%(group_by_cluster)s) (cortex_distributor_replication_factor{%(distributor)s}))
        ||| % ($._config) {
          ingester: $.appMatcher($._config.app_names.ingester),
          distributor: $.appMatcher($._config.app_names.distributor),
        }, format='short') +
        $.panelDescription(
          title,
          |||
            The number of series not yet flushed to object storage that are held in ingester memory.
          |||
        ),
      )
      .addPanel(
        local title = 'Exemplars in ingesters';
        $.panel(title) +
        $.statPanel(|||
          sum(cortex_ingester_tsdb_exemplar_exemplars_in_storage{%(ingester)s}
          / on(%(group_by_cluster)s) group_left
          max by (%(group_by_cluster)s) (cortex_distributor_replication_factor{%(distributor)s}))
        ||| % ($._config) {
          ingester: $.appMatcher($._config.app_names.ingester),
          distributor: $.appMatcher($._config.app_names.distributor),
        }, format='short') +
        $.panelDescription(
          title,
          |||
            Number of TSDB exemplars currently in ingesters' storage.
          |||
        ),
      )
      .addPanel(
        $.panel('Tenants') +
        $.statPanel('count(count by(user) (cortex_ingester_active_series{%s}))' % $.appMatcher($._config.app_names.ingester), format='short')
      )
      .addPanelIf(
        $._config.gateway_enabled,
        $.panel('Requests / sec') +
        $.statPanel('sum(rate(cortex_request_duration_seconds_count{%s, route=~"%s"}[$__rate_interval]))' % [$.appMatcher($._config.app_names.gateway), $.queries.write_http_routes_regex], format='reqps')
      )
    )
    .addRowIf(
      $._config.gateway_enabled,
      $.row('Gateway')
      .addPanel(
        $.panel('Requests / sec') +
        $.qpsPanel($.queries.gateway.writeRequestsPerSecond)
      )
      .addPanel(
        $.panel('Latency') +
        utils.latencyRecordingRulePanel('cortex_request_duration_seconds', $.appSelector($._config.app_names.gateway) + [utils.selector.re('route', $.queries.write_http_routes_regex)])
      )
      .addPanel(
        $.timeseriesPanel('Per %s p99 latency' % $._config.per_instance_label) +
        $.hiddenLegendQueryPanel(
          'histogram_quantile(0.99, sum by(le, %s) (rate(cortex_request_duration_seconds_bucket{%s, route=~"%s"}[$__rate_interval])))' % [$._config.per_instance_label, $.appMatcher($._config.app_names.gateway), $.queries.write_http_routes_regex], ''
        )
      )
    )
    .addRow(
      $.row('Distributor')
      .addPanel(
        $.panel('Requests / sec') +
        $.qpsPanel($.queries.distributor.writeRequestsPerSecond)
      )
      .addPanel(
        $.panel('Latency') +
        utils.latencyRecordingRulePanel('cortex_request_duration_seconds', $.appSelector($._config.app_names.distributor) + [utils.selector.re('route', '/distributor.Distributor/Push|/httpgrpc.*|%s' % $.queries.write_http_routes_regex)])
      )
      .addPanel(
        $.timeseriesPanel('Per %s p99 latency' % $._config.per_instance_label) +
        $.hiddenLegendQueryPanel(
          'histogram_quantile(0.99, sum by(le, %s) (rate(cortex_request_duration_seconds_bucket{%s, route=~"/distributor.Distributor/Push|/httpgrpc.*|%s"}[$__rate_interval])))' % [$._config.per_instance_label, $.appMatcher($._config.app_names.distributor), $.queries.write_http_routes_regex], ''
        )
      )
    )
    .addRowsIf(std.objectHasAll($._config.injectRows, 'postDistributor'), $._config.injectRows.postDistributor($))
    .addRow(
      $.row('Ingester')
      .addPanel(
        $.panel('Requests / sec') +
        $.qpsPanel('cortex_request_duration_seconds_count{%s,route="/cortex.Ingester/Push"}' % $.appMatcher($._config.app_names.ingester))
      )
      .addPanel(
        $.panel('Latency') +
        utils.latencyRecordingRulePanel('cortex_request_duration_seconds', $.appSelector($._config.app_names.ingester) + [utils.selector.eq('route', '/cortex.Ingester/Push')])
      )
      .addPanel(
        $.timeseriesPanel('Per %s p99 latency' % $._config.per_instance_label) +
        $.hiddenLegendQueryPanel(
          'histogram_quantile(0.99, sum by(le, %s) (rate(cortex_request_duration_seconds_bucket{%s, route="/cortex.Ingester/Push"}[$__rate_interval])))' % [$._config.per_instance_label, $.appMatcher($._config.app_names.ingester)], ''
        )
      )
    )
    .addRowIf(
      $._config.gateway_enabled && $._config.autoscaling.gateway.enabled,
      $.cpuAndMemoryBasedAutoScalingRow('Gateway'),
    )
    .addRowIf(
      $._config.autoscaling.distributor.enabled,
      $.cpuAndMemoryBasedAutoScalingRow('Distributor'),
    )
    .addRow(
      $.kvStoreRow('Distributor - key-value store for high-availability (HA) deduplication', 'distributor', 'distributor-hatracker')
    )
    .addRow(
      $.kvStoreRow('Distributor - key-value store for distributors ring', 'distributor', 'distributor-(lifecycler|ring)')
    )
    .addRow(
      $.kvStoreRow('Ingester - key-value store for the ingesters ring', 'ingester', 'ingester-.*')
    )
    .addRow(
      $.row('Ingester - shipper')
      .addPanel(
        $.panel('Uploaded blocks / sec') +
        $.successFailurePanel(
          'sum(rate(cortex_ingester_shipper_uploads_total{%s}[$__rate_interval])) - sum(rate(cortex_ingester_shipper_upload_failures_total{%s}[$__rate_interval]))' % [$.appMatcher($._config.app_names.ingester), $.appMatcher($._config.app_names.ingester)],
          'sum(rate(cortex_ingester_shipper_upload_failures_total{%s}[$__rate_interval]))' % $.appMatcher($._config.app_names.ingester),
        ) +
        $.panelDescription(
          'Uploaded blocks / sec',
          |||
            The rate of blocks being uploaded from the ingesters
            to object storage.
          |||
        ) +
        $.stack,
      )
      .addPanel(
        $.panel('Upload latency') +
        $.latencyPanel('thanos_objstore_bucket_operation_duration_seconds', '{%s,component="ingester",operation="upload"}' % $.appMatcher($._config.app_names.ingester)) +
        $.panelDescription(
          'Upload latency',
          |||
            The average, median (50th percentile), and 99th percentile time
            the ingesters take to upload blocks to object storage.
          |||
        ),
      )
    )
    .addRow(
      $.row('Ingester - TSDB head')
      .addPanel(
        $.panel('Compactions / sec') +
        $.successFailurePanel(
          'sum(rate(cortex_ingester_tsdb_compactions_total{%s}[$__rate_interval]))' % [$.appMatcher($._config.app_names.ingester)],
          'sum(rate(cortex_ingester_tsdb_compactions_failed_total{%s}[$__rate_interval]))' % $.appMatcher($._config.app_names.ingester),
        ) +
        $.panelDescription(
          'Compactions per second',
          |||
            Ingesters maintain a local TSDB per-tenant on disk. Each TSDB maintains a head block for each
            active time series; these blocks get periodically compacted (by default, every 2h).
            This panel shows the rate of compaction operations across all TSDBs on all ingesters.
          |||
        ) +
        $.stack,
      )
      .addPanel(
        $.panel('Compactions latency') +
        $.latencyPanel('cortex_ingester_tsdb_compaction_duration_seconds', '{%s}' % $.appMatcher($._config.app_names.ingester)) +
        $.panelDescription(
          'Compaction latency',
          |||
            The average, median (50th percentile), and 99th percentile time ingesters take to compact TSDB head blocks
            on the local filesystem.
          |||
        ),
      )
    )
    .addRow(
      $.row('Ingester - TSDB write ahead log (WAL)')
      .addPanel(
        $.panel('WAL truncations / sec') +
        $.successFailurePanel(
          'sum(rate(cortex_ingester_tsdb_wal_truncations_total{%s}[$__rate_interval])) - sum(rate(cortex_ingester_tsdb_wal_truncations_failed_total{%s}[$__rate_interval]))' % [$.appMatcher($._config.app_names.ingester), $.appMatcher($._config.app_names.ingester)],
          'sum(rate(cortex_ingester_tsdb_wal_truncations_failed_total{%s}[$__rate_interval]))' % $.appMatcher($._config.app_names.ingester),
        ) +
        $.panelDescription(
          'WAL truncations per second',
          |||
            The WAL is truncated each time a new TSDB block is written. This panel measures the rate of
            truncations.
          |||
        ) +
        $.stack,
      )
      .addPanel(
        $.panel('Checkpoints created / sec') +
        $.successFailurePanel(
          'sum(rate(cortex_ingester_tsdb_checkpoint_creations_total{%s}[$__rate_interval])) - sum(rate(cortex_ingester_tsdb_checkpoint_creations_failed_total{%s}[$__rate_interval]))' % [$.appMatcher($._config.app_names.ingester), $.appMatcher($._config.app_names.ingester)],
          'sum(rate(cortex_ingester_tsdb_checkpoint_creations_failed_total{%s}[$__rate_interval]))' % $.appMatcher($._config.app_names.ingester),
        ) +
        $.panelDescription(
          'Checkpoints created per second',
          |||
            Checkpoints are created as part of the WAL truncation process.
            This metric measures the rate of checkpoint creation.
          |||
        ) +
        $.stack,
      )
      .addPanel(
        $.panel('WAL truncations latency (includes checkpointing)') +
        $.queryPanel('sum(rate(cortex_ingester_tsdb_wal_truncate_duration_seconds_sum{%s}[$__rate_interval])) / sum(rate(cortex_ingester_tsdb_wal_truncate_duration_seconds_count{%s}[$__rate_interval]))' % [$.appMatcher($._config.app_names.ingester), $.appMatcher($._config.app_names.ingester)], 'avg') +
        { yaxes: $.yaxes('s') } +
        $.panelDescription(
          'WAL truncations latency (including checkpointing)',
          |||
            Average time taken to perform a full WAL truncation,
            including the time taken for the checkpointing to complete.
          |||
        ),
      )
      .addPanel(
        $.panel('Corruptions / sec') +
        $.queryPanel([
          'sum(rate(cortex_ingester_tsdb_wal_corruptions_total{%s}[$__rate_interval]))' % $.appMatcher($._config.app_names.ingester),
          'sum(rate(cortex_ingester_tsdb_mmap_chunk_corruptions_total{%s}[$__rate_interval]))' % $.appMatcher($._config.app_names.ingester),
        ], [
          'WAL',
          'mmap-ed chunks',
        ]) +
        $.stack + {
          yaxes: $.yaxes('ops'),
          aliasColors: {
            WAL: '#E24D42',
            'mmap-ed chunks': '#E28A42',
          },
        },
      )
    )
    .addRow(
      $.row('Exemplars')
      .addPanel(
        local title = 'Distributor exemplars incoming rate';
        $.panel(title) +
        $.queryPanel(
          'sum(%(group_prefix_apps)s:cortex_distributor_exemplars_in:rate5m{%(app)s})'
          % { app: $.appMatcher($._config.app_names.distributor), group_prefix_apps: $._config.group_prefix_apps },
          'incoming exemplars',
        ) +
        { yaxes: $.yaxes('ex/s') } +
        $.panelDescription(
          title,
          |||
            The rate of exemplars that have come in to the distributor, including rejected or deduped exemplars.
          |||
        ),
      )
      .addPanel(
        local title = 'Distributor exemplars received rate';
        $.panel(title) +
        $.queryPanel(
          'sum(%(group_prefix_apps)s:cortex_distributor_received_exemplars:rate5m{%(app)s})'
          % { app: $.appMatcher($._config.app_names.distributor), group_prefix_apps: $._config.group_prefix_apps },
          'received exemplars',
        ) +
        { yaxes: $.yaxes('ex/s') } +
        $.panelDescription(
          title,
          |||
            The rate of received exemplars, excluding rejected and deduped exemplars.
            This number can be sensibly lower than incoming rate because we dedupe the HA sent exemplars, and then reject based on time, see `cortex_discarded_exemplars_total` for specific reasons rates.
          |||
        ),
      )
      .addPanel(
        local title = 'Ingester ingested exemplars rate';
        $.panel(title) +
        $.queryPanel(
          |||
            sum(
              %(group_prefix_apps)s:cortex_ingester_ingested_exemplars:rate5m{%(ingester)s}
              / on(%(group_by_cluster)s) group_left
              max by (%(group_by_cluster)s) (cortex_distributor_replication_factor{%(distributor)s})
            )
          ||| % {
            ingester: $.appMatcher($._config.app_names.ingester),
            distributor: $.appMatcher($._config.app_names.distributor),
            group_by_cluster: $._config.group_by_cluster,
            group_prefix_apps: $._config.group_prefix_apps,
          },
          'ingested exemplars',
        ) +
        { yaxes: $.yaxes('ex/s') } +
        $.panelDescription(
          title,
          |||
            The rate of exemplars ingested in the ingesters.
            Every exemplar is sent to the replication factor number of ingesters, so the sum of rates from all ingesters is divided by the replication factor.
            This ingested exemplars rate should match the distributor's received exemplars rate.
          |||
        ),
      )
      .addPanel(
        local title = 'Ingester appended exemplars rate';
        $.panel(title) +
        $.queryPanel(
          |||
            sum(
              %(group_prefix_apps)s:cortex_ingester_tsdb_exemplar_exemplars_appended:rate5m{%(ingester)s}
              / on(%(group_by_cluster)s) group_left
              max by (%(group_by_cluster)s) (cortex_distributor_replication_factor{%(distributor)s})
            )
          ||| % {
            ingester: $.appMatcher($._config.app_names.ingester),
            distributor: $.appMatcher($._config.app_names.distributor),
            group_by_cluster: $._config.group_by_cluster,
            group_prefix_apps: $._config.group_prefix_apps,
          },
          'appended exemplars',
        ) +
        { yaxes: $.yaxes('ex/s') } +
        $.panelDescription(
          title,
          |||
            The rate of exemplars appended in the ingesters.
            This can be lower than ingested exemplars rate since TSDB does not append the same exemplar twice, and those can be frequent.
          |||
        ),
      )
    ),
}
