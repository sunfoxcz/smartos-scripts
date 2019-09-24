# SmartOS Scripts

Few console utilities fo help manage raw SmartOS hosts.

## migrate_vm.pl

Migrates VM to another machine.

### Usage

```bash
$ migrate_vm.pl <vm_uuid> <target_host> <prepare|migrate|cleanup> [--force|-f]
```

### Example output

1. Prepare operation
```bash
Checking local VM
 * UUID: 478ebd93-b506-47b0-b483-65e243f5146f
 * Alias: test-server
 * Brand: kvm
 * State: running

Checking target machine
 * dataset zones/478ebd93-b506-47b0-b483-65e243f5146f-disk0 is clone of zones/47f66e34-2c6d-11e8-bef9-4780fac9ac03@final
 * importing image 47f66e34-2c6d-11e8-bef9-4780fac9ac03
Importing 47f66e34-2c6d-11e8-bef9-4780fac9ac03 (centos-7@20180320) from "https://images.joyent.com"
Gather image 47f66e34-2c6d-11e8-bef9-4780fac9ac03 ancestry
Must download and install 1 image (414.7 MiB)
Downloaded image 47f66e34-2c6d-11e8-bef9-4780fac9ac03 (414.7 MiB)
Imported image 47f66e34-2c6d-11e8-bef9-4780fac9ac03 (centos-7@20180320)

Creating snapshots
 * creating snapshot zones/478ebd93-b506-47b0-b483-65e243f5146f@today
 * creating snapshot zones/478ebd93-b506-47b0-b483-65e243f5146f-disk0@today

Sending datasets to sm12.sunfox.cz
 * sending zones/478ebd93-b506-47b0-b483-65e243f5146f@today
 233KiB 0:00:02 [77,9KiB/s] [77,9KiB/s]
 * sending zones/478ebd93-b506-47b0-b483-65e243f5146f-disk0@today
11,9GiB 0:10:31 [19,3MiB/s] [19,3MiB/s]
```

2. Migrate operation
```bash
hecking local VM
 * UUID: 478ebd93-b506-47b0-b483-65e243f5146f
 * Alias: test-server
 * Brand: kvm
 * State: running
 * stopping local VM

Checking target machine

Creating snapshots
 * creating snapshot zones/478ebd93-b506-47b0-b483-65e243f5146f@migrate
 * creating snapshot zones/478ebd93-b506-47b0-b483-65e243f5146f-disk0@migrate
 * creating snapshot zones/cores/478ebd93-b506-47b0-b483-65e243f5146f@migrate

Sending datasets to sm12.sunfox.cz
 * sending zones/478ebd93-b506-47b0-b483-65e243f5146f@today increments
39,8KiB 0:00:00 [ 256KiB/s] [ 256KiB/s]
 * sending zones/478ebd93-b506-47b0-b483-65e243f5146f-disk0@today increments
2,35MiB 0:00:00 [10,1MiB/s] [10,1MiB/s]
 * sending zones/cores/478ebd93-b506-47b0-b483-65e243f5146f@migrate
46,6KiB 0:00:01 [  24KiB/s] [  24KiB/s]

Target machine
 * creating remote VM config
 * starting remote VM

Destroying migrate datasets
 * destroying snapshot zones/478ebd93-b506-47b0-b483-65e243f5146f@migrate
 * destroying snapshot zones/478ebd93-b506-47b0-b483-65e243f5146f-disk0@migrate
 * destroying snapshot zones/cores/478ebd93-b506-47b0-b483-65e243f5146f@migrate
```

3. Cleanup operation
```bash
Checking local VM
 * UUID: 478ebd93-b506-47b0-b483-65e243f5146f
 * Alias: test-server
 * Brand: kvm
 * State: stopped

Target machine
 * destroying snapshot zones/478ebd93-b506-47b0-b483-65e243f5146f@today
 * destroying snapshot zones/478ebd93-b506-47b0-b483-65e243f5146f-disk0@today

Local machine
 * deleting VM
 * deleting logadm entries

Backup server
 * raname zones/backup/old-node/test-server to zones/backup/new-ndde/test-server
 * raname zones/backup/old-node/test-server-disk0 to zones/backup/new-node/test-server-disk0
```
