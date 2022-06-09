Query alerts

```sh
yq ./tests/golden/defaults/rook-ceph/rook-ceph/40_alertrules.yaml -o=json | jq '.spec.groups[] | {group: .name, alert: (.rules[] | {name: .alert, summary: .annotations.summary})} | .group + "\t" + .alert.name + "\t" + .alert.summary' -r | sort
```

Output

```
cluster health	SYN_CephHealthError	Cluster is in an ERROR state
cluster health	SYN_CephHealthWarning	Cluster is in a WARNING state
generic	SYN_CephDaemonCrash	One or more Ceph daemons have crashed, and are pending acknowledgement
healthchecks	SYN_CephSlowOps	MON/OSD operations are slow to complete
mds	SYN_CephFilesystemDamaged	Ceph filesystem is damaged.
mds	SYN_CephFilesystemDegraded	Ceph filesystem is degraded
mds	SYN_CephFilesystemFailureNoStandby	Ceph MDS daemon failed, no further standby available
mds	SYN_CephFilesystemInsufficientStandby	Ceph filesystem standby daemons too low
mds	SYN_CephFilesystemMDSRanksLow	Ceph MDS daemon count is lower than configured
mds	SYN_CephFilesystemOffline	Ceph filesystem is offline
mds	SYN_CephFilesystemReadOnly	Ceph filesystem in read only mode, due to write error(s)
mgr	SYN_CephMgrModuleCrash	A mgr module has recently crashed
mgr	SYN_CephMgrPrometheusModuleInactive	Ceph's mgr/prometheus module is not available
mon	SYN_CephMonClockSkew	Clock skew across the Monitor hosts detected
mon	SYN_CephMonDiskspaceCritical	Disk space on at least one monitor is critically low
mon	SYN_CephMonDiskspaceLow	Disk space on at least one monitor is approaching full
mon	SYN_CephMonDown	One of more ceph monitors are down
mon	SYN_CephMonDownQuorumAtRisk	Monitor quorum is at risk
nodes	SYN_CephNodeDiskspaceWarning	Host filesystem freespace is getting low
nodes	SYN_CephNodeInconsistentMTU	MTU settings across Ceph hosts are inconsistent
nodes	SYN_CephNodeNetworkPacketDrops	One or more Nics is seeing packet drops
nodes	SYN_CephNodeNetworkPacketErrors	One or more Nics is seeing packet errors
nodes	SYN_CephNodeRootFilesystemFull	Root filesystem is dangerously full
osd	SYN_CephDeviceFailurePredicted	Device(s) have been predicted to fail soon
osd	SYN_CephDeviceFailurePredictionTooHigh	Too many devices have been predicted to fail, unable to resolve
osd	SYN_CephDeviceFailureRelocationIncomplete	A device failure is predicted, but unable to relocate data
osd	SYN_CephOSDBackfillFull	OSD(s) too full for backfill operations
osd	SYN_CephOSDDown	An OSD has been marked down/unavailable
osd	SYN_CephOSDDownHigh	More than 10% of OSDs are down
osd	SYN_CephOSDFlapping	Network issues are causing OSD's to flap (mark each other out)
osd	SYN_CephOSDFull	OSD(s) is full, writes blocked
osd	SYN_CephOSDHostDown	An OSD host is offline
osd	SYN_CephOSDInternalDiskSizeMismatch	OSD size inconsistency error
osd	SYN_CephOSDNearFull	OSD(s) running low on free space (NEARFULL)
osd	SYN_CephOSDReadErrors	Device read errors detected
osd	SYN_CephOSDTimeoutsClusterNetwork	Network issues delaying OSD heartbeats (cluster network)
osd	SYN_CephOSDTimeoutsPublicNetwork	Network issues delaying OSD heartbeats (public network)
osd	SYN_CephOSDTooManyRepairs	OSD has hit a high number of read errors
osd	SYN_CephPGImbalance	PG allocations are not balanced across devices
pgs	SYN_CephPGBackfillAtRisk	Backfill operations are blocked, due to lack of freespace
pgs	SYN_CephPGNotDeepScrubbed	Placement group(s) have not been deep scrubbed
pgs	SYN_CephPGNotScrubbed	Placement group(s) have not been scrubbed
pgs	SYN_CephPGRecoveryAtRisk	OSDs are too full for automatic recovery
pgs	SYN_CephPGUnavilableBlockingIO	Placement group is unavailable, blocking some I/O
pgs	SYN_CephPGsDamaged	Placement group damaged, manual intervention needed
pgs	SYN_CephPGsHighPerOSD	Placement groups per OSD is too high
pgs	SYN_CephPGsInactive	One or more Placement Groups are inactive
pgs	SYN_CephPGsUnclean	One or more platcment groups are marked unclean
pools	SYN_CephPoolBackfillFull	Freespace in a pool is too low for recovery/rebalance
pools	SYN_CephPoolFull	Pool is full - writes are blocked
pools	SYN_CephPoolNearFull	One or more Ceph pools are getting full
rados	SYN_CephObjectMissing	Object(s) has been marked UNFOUND
syn-rook-ceph-additional.alerts	SYN_RookCephOperatorScaledDown	rook-ceph operator scaled to 0 for more than 1 hour.
```