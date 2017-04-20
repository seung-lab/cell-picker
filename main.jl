#Pkg.add("MySQL")
#Pkg.add("JSON")
#Pkg.add("DataFrames")
#Pkg.add("Distances")
#Pkg.add("Requests")
#Pkg.add("ArgParse")

using MySQL
import JSON
import DataFrames
import Distances
import Requests: get
import ArgParse

const SQL_CONF = JSON.parsefile("mysql.config.json")
const NG_CONF  = JSON.parsefile("neuroglancer.config.json")

@enum COORDINATE_SYSTEM NEUROGLANCER=1 EYEWIRE=2

type BBox{T}
    bbox_min::Vector{T}
    bbox_max::Vector{T}

    function BBox(xmin::T, ymin::T, zmin::T, xmax::T, ymax::T, zmax::T)
        bbox_min = Vector{T}()
        bbox_max = Vector{T}()
        bbox_min = [xmin, ymin, zmin]
        bbox_max = [xmax, ymax, zmax]
        return new(bbox_min,bbox_max)
    end
end

# Eyewire dataset type with all the potentially useful data
immutable Dataset
    id::Unsigned
    name::AbstractString
    voxel_resolution::Vector{Float32}
    physical_overlap::Vector{Float32}
    volume_voxel_size::Vector{Integer}
    bounding_box::BBox{Integer}
    hypersquare_bucket::AbstractString
    offset::Vector{Integer}
    segment_id_type::DataType

    function Dataset(dataset::DataFrames.DataFrame)
        voxel_resolution   = Vector{Float32}()
        physical_overlap   = Vector{Float32}()
        volume_voxel_size  = Vector{Integer}()
        offset             = Vector{Integer}()
        
        id                 = dataset[1][1]
        name               = dataset[2][1]
        voxel_resolution   = [ dataset[3][1], dataset[4][1], dataset[5][1] ]
        physical_overlap   = [ dataset[6][1], dataset[7][1], dataset[8][1] ]
        volume_voxel_size  = [ dataset[9][1], dataset[10][1], dataset[11][1] ]
        bounding_box       = BBox{Integer}(dataset[15][1], dataset[16][1], dataset[17][1], dataset[12][1], dataset[13][1], dataset[14][1])
        hypersquare_bucket = string(dataset[18][1],'/')

        ng_info            = NG_CONF["datasets"][string(id)]
        offset             = ng_info["offset"]

        if     ng_info["segment_id_type"] == "UInt8"  segment_id_type = UInt8
        elseif ng_info["segment_id_type"] == "UInt16" segment_id_type = UInt16
        elseif ng_info["segment_id_type"] == "UInt32" segment_id_type = UInt32
        elseif ng_info["segment_id_type"] == "UInt64" segment_id_type = UInt64
        elseif ng_info["segment_id_type"] == "Int8"   segment_id_type = Int8
        elseif ng_info["segment_id_type"] == "Int16"  segment_id_type = Int16
        elseif ng_info["segment_id_type"] == "Int32"  segment_id_type = Int32
        elseif ng_info["segment_id_type"] == "Int64"  segment_id_type = Int64 end


        new(id, name, voxel_resolution, physical_overlap, volume_voxel_size, bounding_box, hypersquare_bucket, offset, segment_id_type)
    end
end

immutable Coords
    ew_dataset::Dataset
    ew_coords::Vector{Float32}
    ng_coords::Vector{Float32}

    function Coords{T<:Real}(dataset::Dataset, coord_system::COORDINATE_SYSTEM, coords::Vector{T})
        if coord_system == NEUROGLANCER::COORDINATE_SYSTEM
            ng_coords = coords
            ew_coords = (ng_coords - dataset.offset) .* dataset.voxel_resolution
            return new(dataset, ew_coords, ng_coords)
        else # coord_system == EYEWIRE::COORDINATE_SYSTEM
            ew_coords = coords
            ng_coords = (ew_coords ./ dataset.voxel_resolution) + dataset.offset
            return new(dataset, ew_coords, ng_coords)
        end
    end
end

function parse_user_input(str)
    args = matchall(r"(?:(--[^\s=]+)|\"([^\"]+)\"|([^\s=]+))", str)
    args = map(s -> strip(s, '\"'), args)

    coord_settings = ArgParse.ArgParseSettings()   # For adding cells using Neuroglancer or Eyewire coordinates
    segment_settings = ArgParse.ArgParseSettings() # For adding cells using Eyewire task and segment IDs
    ArgParse.@add_arg_table coord_settings begin
        "coord_system"
            help = "Coordinate type, must be NG (Neuroglancer) or EW (Eyewire)"
            required = true
            arg_type = String
        "x"
            help = "x coordinate"
            required = true
            arg_type = Int
        "y"
            help = "y coordinate"
            required = true
            arg_type = Int
        "z"
            help = "z coordinate"
            required = true
            arg_type = Int
        "--cell_id"
            help = "The new cell id"
            arg_type = UInt32
            default = UInt32(0)
        "--cell_name"
            help = "The cell name"
            arg_type = String
            default = ""
        "--description"
            help = "A description of the cell"
            arg_type = String
            default = ""
        "--threshtype"
            help = "Controls when new tasks are spawned. Don't change unless you know what you are doing."
            arg_type = String
            default = "spawnWithOne"
        "--display"
            help = "0 or 1. Specifies whether the cell will be visible in the cell selection menu."
            arg_type = UInt8
            default = UInt8(1)
        "--detect_duplicates"
            help = "0 or 1. Controls duplicate detection. Don't change unless you know what you are doing."
            arg_type = UInt8
            default = UInt8(1)
        "--difficulty"
            help = "[1-3. Used to restrict access to cell for certain players. Probably buggy for new datasets. Don't change unless you know what you are doing."
            arg_type = UInt8
            default = UInt8(1)
    end

    ArgParse.@add_arg_table segment_settings begin
        "task_id"
            help = "Eyewire task ID"
            required = true
            arg_type = UInt32
        "segment_id"
            help = "Segment ID within the given task."
            required = true
            arg_type = UInt32
        "--cell_id"
            help = "The new cell id"
            arg_type = UInt32
            default = UInt32(0)
        "--cell_name"
            help = "The cell name"
            arg_type = String
            default = ""
        "--description"
            help = "A description of the cell"
            arg_type = String
            default = ""
        "--threshtype"
            help = "Controls when new tasks are spawned. Don't change unless you know what you are doing."
            arg_type = String
            default = "spawnWithOne"
        "--display"
            help = "0 or 1. Specifies whether the cell will be visible in the cell selection menu."
            arg_type = UInt8
            default = UInt8(1)
        "--detect_duplicates"
            help = "0 or 1. Controls duplicate detection. Don't change unless you know what you are doing."
            arg_type = UInt8
            default = UInt8(1)
        "--difficulty"
            help = "[1-3. Used to restrict access to cell for certain players. Probably buggy for new datasets. Don't change unless you know what you are doing."
            arg_type = UInt8
            default = UInt8(1)
    end

    if isnumber(args[1])
        return ArgParse.parse_args(args, segment_settings)
    else
        return ArgParse.parse_args(args, coord_settings)
    end
end

"""
`get_cell_count(hndl::MySQLHandle, dataset::Dataset)`

Returns number of cells in specified dataset.
"""
function get_cell_count(hndl::MySQLHandle, dataset::Dataset)
    result = mysql_execute(hndl, "SELECT COUNT(*) FROM cells WHERE dataset_id = $(dataset.id);")
    return result[1][1]
end

"""
`get_seed(hndl::MySQLHandle, dataset::Dataset, coordinates::Coords)`

Calculates and retrieves information about the best matching volume and segment ID for the specified coordinates from the database.
The segment ID lookup requires downloading the LZMA segmentation file.
Note: Julia doesn't have a LZMA package, hence the file is stored to disk (creating a tmp dir in the working direcory),
decompressed using the systems unlzma command and then read back to Julia.

Returns a tuple with information about the volume as DataFrame, and the segment_id
"""
function get_seed(hndl::MySQLHandle, dataset::Dataset, coordinates::Coords)
    # Get the volume that contains most context for the given coordinates
    best_volume = nothing
    shortest_distance::Float32 = Inf
    for row in MySQLRowIterator(hndl, "SELECT id, path, xmin, ymin, zmin, xmax, ymax, zmax FROM volumes
                                       WHERE dataset = $(dataset.id) AND datatype = 2 AND
                                           $(coordinates.ew_coords[1]) BETWEEN xmin AND xmax AND
                                           $(coordinates.ew_coords[2]) BETWEEN ymin AND ymax AND
                                           $(coordinates.ew_coords[3]) BETWEEN zmin AND zmax;")
                        
        volume_center::Vector{Float32} = [0.5 * (get(row[3]) + get(row[6])), 0.5 * (get(row[4]) + get(row[7])), 0.5 * (get(row[5]) + get(row[8]))]
        dist = Distances.chebyshev(coordinates.ew_coords, volume_center)

        if dist < shortest_distance
            shortest_distance = dist
            best_volume = row
        end
    end

    if best_volume == nothing
        return (nothing, NaN)
    end

    volume_path = best_volume[2]
    volume_bounds = BBox{Integer}(get(best_volume[3]), get(best_volume[4]), get(best_volume[5]), get(best_volume[6]), get(best_volume[7]), get(best_volume[8]))

    if !isfile("./tmp/$(dataset.hypersquare_bucket)$(volume_path)segmentation.lzma")
        mkpath("./tmp/$(dataset.hypersquare_bucket)$(volume_path)")

        segmentation = Requests.get("https://storage.googleapis.com/$(dataset.hypersquare_bucket)$(volume_path)segmentation.lzma")
        Requests.save(segmentation, "./tmp/$(dataset.hypersquare_bucket)$(volume_path)segmentation.lzma")
    end

    if !isfile("./tmp/$(dataset.hypersquare_bucket)$(volume_path)segmentation")
        run(`unlzma ./tmp/$(dataset.hypersquare_bucket)$(volume_path)segmentation.lzma`)
    end

    segFile = open("./tmp/$(dataset.hypersquare_bucket)$(volume_path)segmentation", "r")
    segData = reinterpret(dataset.segment_id_type, read(segFile))
    close(segFile)
    segArray = reshape(segData, tuple(dataset.volume_voxel_size[1], dataset.volume_voxel_size[2], dataset.volume_voxel_size[3]))

    volume_coordinates = convert(Vector{Integer}, round((coordinates.ew_coords - volume_bounds.bbox_min) ./ dataset.voxel_resolution))
    volume_coordinates[1] = clamp(volume_coordinates[1], 0, dataset.volume_voxel_size[1]) + 1
    volume_coordinates[2] = clamp(volume_coordinates[2], 0, dataset.volume_voxel_size[2]) + 1
    volume_coordinates[3] = clamp(volume_coordinates[3], 0, dataset.volume_voxel_size[3]) + 1

    return (best_volume, segArray[volume_coordinates[1], volume_coordinates[2], volume_coordinates[3]])
end

function get_volume(hndl::MySQLHandle, dataset::Dataset, task_id::Unsigned)
    result = mysql_execute(hndl, "SELECT v.id, v.path FROM volumes v
                                  JOIN tasks t ON t.segmentation_id = v.id
                                  WHERE v.dataset = $(dataset.id) AND t.id = $(task_id);")
    if size(result) == (0,2)
        return nothing
    end
    return [result[1][1], result[2][1]]
end

"""
`get_duplicates(hndl::MySQLHandle, vol_id::Unsigned, segment_id::Unsigned)`

Checks if other tasks/cells in the database already contain the specified segment_id

An array of tuples with (cell_id, task_id) is returned, representing the duplicates
"""
function get_duplicates(hndl::MySQLHandle, vol_id::Unsigned, segment_id::Unsigned)
    duplicates = []
    for row in MySQLRowIterator(hndl, "SELECT c.id, t.id, v.segments
                                       FROM validations v
                                       JOIN tasks t ON v.task_id = t.id
                                       JOIN cells c ON c.id = t.cell
                                       JOIN volumes vol ON vol.id = t.segmentation_id
                                       WHERE t.status IN (0,10,11) AND v.status = 9 AND c.detect_duplicates = 1 AND vol.id = $(vol_id);")
        segments = JSON.parse(get(row[3]))
        if haskey(segments, string(segment_id))
            push!(duplicates, (row[1], row[2]))
        end
    end

    return duplicates
end

function spawn_cell(hndl::MySQLHandle, dataset::Dataset, coordinates::Coords;
                    id=0, name="", description="", threshtype="spawnWithOne", display=1, detect_duplicates=1, difficulty=1)
    result = nothing

    volume, seg_id = get_seed(hndl, dataset, coordinates)
    if volume == nothing || isnan(seg_id)
        println("No volume or segment found for given coordinates.")
        return nothing
    end

    if seg_id == 0
        println("Can't spawn cell at Neuroglancer coordinates ($(coordinates.ng_coords[1]), $(coordinates.ng_coords[2]), $(coordinates.ng_coords[3])). Corresponding Segment ID is 0.")
        return nothing
    end

    duplicates = get_duplicates(hndl, convert(Unsigned, volume[1]), seg_id)
    if !isempty(duplicates)
        println("Can't spawn cell at Neuroglancer coordinates ($(coordinates.ng_coords[1]), $(coordinates.ng_coords[2]), $(coordinates.ng_coords[3])). One or more duplicate tasks detected:")
        for duplicate in duplicates
            println("* Cell $(duplicate[1]), Task $(duplicate[2])")
        end
        return nothing
    end

    println("Best match: Volume ID $(volume[1]), $(dataset.hypersquare_bucket)$(volume[2]) with segment $(seg_id)")

    cell_count = get_cell_count(hndl, dataset)
    if name == ""
        name = string(NG_CONF["datasets"][string(dataset.id)]["cellname_template"], cell_count)
    end

    # Make cell insertion a Transaction, in case something goes wrong
    mysql_execute(hndl, "START TRANSACTION;")

    sql = "INSERT INTO cells ("
    if id > 0 sql = string(sql, "id, ") end
    sql = string(sql, "name, description, threshtype, display, dataset_id, detect_duplicates, difficulty) VALUES (")
    if id > 0 sql = string(sql, id, ", ") end
    sql = string(sql, "'", name, "', '", description, "', '", threshtype,"', ", display, ", ", dataset.id, ", ", detect_duplicates, ", ", difficulty, ");")

    println(sql)
    result = mysql_execute(hndl, sql)
    println(result)

    if id == 0
        sql = "SELECT id FROM cells
               WHERE name = '$(name)' AND threshtype = '$(threshtype)' AND display = $(display) AND
                     dataset_id = $(dataset.id) AND detect_duplicates = $(detect_duplicates) AND
                     difficulty = $(difficulty) AND created > NOW() - INTERVAL 1 MINUTE;"
        
        result = mysql_execute(hndl, sql)
        if size(result) != (1,1)
            println("Couldn't identify newly generated cell! Reverting...")
            mysql_execute(hndl, "ROLLBACK;")
            return nothing
        end
        id = result[1][1]
    end

    sql = "CALL task_create_seed($(id), $(seg_id), '$(volume[2])');";
    println(sql)
    result = mysql_execute(hndl, sql)
    println(result)

    mysql_execute(hndl, "COMMIT;")
    return result
end

function spawn_cell(hndl::MySQLHandle, dataset::Dataset, task_id::UInt32, seg_id::UInt32;
                    id=0, name="", description="", threshtype="spawnWithOne", display=1, detect_duplicates=1, difficulty=1)
    result = nothing

    volume = get_volume(hndl, dataset, task_id)
    if volume == nothing
        println("No volume found for task ID $(task_id) in dataset $(dataset.name).")
        return nothing
    end

    if seg_id == 0
        println("Invalid segment ID: 0")
        return nothing
    end

    duplicates = get_duplicates(hndl, convert(Unsigned, volume[1]), seg_id)
    if !isempty(duplicates)
        println("Can't spawn cell using task $(task_id) and segment $(seg_id). One or more duplicate tasks detected:")
        for duplicate in duplicates
            println("* Cell $(duplicate[1]), Task $(duplicate[2])")
        end
        return nothing
    end

    println("Best match: Volume ID $(volume[1]), $(dataset.hypersquare_bucket)$(volume[2]) with segment $(seg_id)")

    cell_count = get_cell_count(hndl, dataset)
    if name == ""
        name = string(NG_CONF["datasets"][string(dataset.id)]["cellname_template"], cell_count)
    end

    # Make cell insertion a Transaction, in case something goes wrong
    mysql_execute(hndl, "START TRANSACTION;")

    sql = "INSERT INTO cells ("
    if id > 0 sql = string(sql, "id, ") end
    sql = string(sql, "name, description, threshtype, display, dataset_id, detect_duplicates, difficulty) VALUES (")
    if id > 0 sql = string(sql, id, ", ") end
    sql = string(sql, "'", name, "', '", description, "', '", threshtype,"', ", display, ", ", dataset.id, ", ", detect_duplicates, ", ", difficulty, ");")

    println(sql)
    result = mysql_execute(hndl, sql)
    println(result)

    if id == 0
        sql = "SELECT id FROM cells
               WHERE name = '$(name)' AND threshtype = '$(threshtype)' AND display = $(display) AND
                     dataset_id = $(dataset.id) AND detect_duplicates = $(detect_duplicates) AND
                     difficulty = $(difficulty) AND created > NOW() - INTERVAL 1 MINUTE;"
        
        result = mysql_execute(hndl, sql)
        if size(result) != (1,1)
            println("Couldn't identify newly generated cell! Reverting...")
            mysql_execute(hndl, "ROLLBACK;")
            return nothing
        end
        id = result[1][1]
    end

    sql = "CALL task_create_seed($(id), $(seg_id), '$(volume[2])');";
    println(sql)
    result = mysql_execute(hndl, sql)
    println(result)

    mysql_execute(hndl, "COMMIT;")
    return result
end

"""
`input(prompt::AbstractString="")`

Read lines from STDIN until an empty line is encountered.

The prompt string, if given, is printed to standard output without a
trailing newline before reading input.
"""
function inputlines(prompt::AbstractString="")
    print(prompt)
    result = []
    while true
        line = chomp(readline())
        if isempty(line) break end
        push!(result,line)
    end
    return result
end

function inputline(prompt::AbstractString="")
    print(prompt)
    return chomp(readline())
end

"""
`get_dataset(hndl::MySQLHandle, dataset_id::Int)`

Retrieves information about a given dataset from the database.

An object of type Dataset is returned
"""
function get_dataset(hndl::MySQLHandle, dataset_id::Unsigned)
    result = mysql_execute(hndl, "SELECT id, name, resolution_x, resolution_y, resolution_z, overlap_x, overlap_y, overlap_z,
                                         volume_voxels_x, volume_voxels_y, volume_voxels_z, xmin, ymin, zmin, xmax, ymax, zmax, cloud_bucket
                                  FROM datasets
                                  WHERE id = $(dataset_id);")
    return Dataset(result)
end



###############################################
#                     MAIN                    #
###############################################
function main()
    # Connect to DB
    sql_conn = nothing
    try
        sql_conn = mysql_connect(SQL_CONF["host"], SQL_CONF["user"], SQL_CONF["password"], SQL_CONF["database"])
        println("Connection to database established.")
    catch
        println("Can't connect to database. Make sure you have an open tunnel to one of the db servers and the configuration in mysql.config.json is correct.")
        println("ssh -fNL 3306:[db_server]:3306 [username]@brainiac2.mit.edu")
        return
    end

    # Load Neuroglancer config
    ng_conf = JSON.parsefile("neuroglancer.config.json")

    # List all available datasets
    println("Available Datasets:\nID\tDataset")
    for row in MySQLRowIterator(sql_conn, "SELECT id, name FROM datasets;")
        println("$(row[1])  $(get(row[2], '-'))")
    end

    # Select dataset
    #dataset_id = 213
    dataset_id = parse(UInt, inputline("Choose dataset ID: "))    ### Uncomment to let user select dataset

    # Retrieve dataset information from DB
    dataset = get_dataset(sql_conn, dataset_id)

    # Request user input
    println("\nPaste Neuroglancer/Eyewire coordinates and cell info:")
    println("Format: NG|EW x y z [--cell_id=123] [--cell_name=\"Cell #1\"] [--description=\"\"]")
    println("                    [--threshtype=\"spawnWithOne\"] [--display=1]")
    println("                    [--detect_duplicates=1] [--difficulty=1]")
    println("\nOr an Eyewire task ID, segment ID and cell info:")
    println("Format: t_id seg_id [--cell_id=123] [--cell_name=\"Cell #1\"] [--description=\"\"]")
    println("                    [--threshtype=\"spawnWithOne\"] [--display=1]")
    println("                    [--detect_duplicates=1] [--difficulty=1]")
    println("\nExample 1: NG 1234 5678 910 --cell_name=\"Test Cell\" --description=\"Soma\"")
    println("Example 2: 1234567 8910 --cell_name=\"Test Cell\" --description=\"Synapse\"")

    rows = inputlines(">")

    println("Processing $(size(rows)) entries")
    for row in rows
        cell_info = parse_user_input(row)
        if (haskey(cell_info, "task_id"))
            spawn_cell(sql_conn, dataset, cell_info["task_id"], cell_info["segment_id"];
                id=cell_info["cell_id"], name=cell_info["cell_name"], description=cell_info["description"],
                threshtype=cell_info["threshtype"], display=cell_info["display"], detect_duplicates=cell_info["detect_duplicates"],
                difficulty=cell_info["difficulty"])
        else
            if lowercase(cell_info["coord_system"]) == "ng"
                coord_system = NEUROGLANCER::COORDINATE_SYSTEM
            elseif lowercase(cell_info["coord_system"]) == "ew"
                coord_system = EYEWIRE::COORDINATE_SYSTEM
            else
                println("$(cell_info["coord_system"]) is not a valid coordinate system ('ew' or 'ng')")
                continue
            end

            coords = Coords(dataset, coord_system, [cell_info["x"], cell_info["y"], cell_info["z"]])
            spawn_cell(sql_conn, dataset, coords;
                id=cell_info["cell_id"], name=cell_info["cell_name"], description=cell_info["description"],
                threshtype=cell_info["threshtype"], display=cell_info["display"], detect_duplicates=cell_info["detect_duplicates"],
                difficulty=cell_info["difficulty"])
        end
    end

    mysql_disconnect(sql_conn)
end

main()
