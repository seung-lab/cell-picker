# Cell picker
Seed new Eyewire cells using Neuroglancer or Eyewire coordinates. Tested with Julia 0.5

* Rename `mysql.config.json.example` to `mysql.config.json` and add credentials
* Open SSH tunnel to one of the DB servers: `ssh -fNL 3306:[db_server]:3306 [username]@brainiac2.mit.edu` Current configuration can be found [in the wiki](https://github.com/seung-lab/omni-web/wiki/EyeWire-Cluster-Status).

Each row must contain the coordinate system (NG|EW) as well as x, y and z coordinates, in this order.
All other values are optional:
* --cell_id; if omitted, will pick the next free spot
* --cell_name; if ommited, will generate a cell name based on the `cellname_template` in `neuroglancer.config.json` and the number of existing cells for the chosen dataset.
* --description; default is empty
* --threshtype; default is "spawnWithOne", which is used to spawn new tasks after a single submission
* --display; default is 1, determines whether the cell will be visible within the cell selection menu in Eyewire
* --detect_duplicates; default is 1, prevents spawning new tasks if a similar consensus exists in another task/cell
* --difficulty; default is 1, used to determine which players can trace the cell.

Examples:
`NG	31973	14720	139	--display 0	--cell_name "Test Cell"`
`EW 239200 155390 747926 --description="Interesting looking branch"`
