
import tables, strutils, sequtils
import os
import threadpool
import readfq
import docopt
import ./seqfu_utils

# Global settings
var
  addCounts, addPath, enforcePe: bool
  isPe: int
  isSe: int

type
  sample = ref object
    name : string         # Required: sample ID

    path : string         # Full path to the containing directory
    file1: string         # Filename R1
    file2: string         # Filename R2
    files: int            # Number of files {sample}* (should be 1 or 2)

    count: int            # Number of raw reads
    index: string         # Illumina Index

    flist: seq[string]    # List of files (for debugging if files > 0)
    fields: Table[string, string]

proc init(s: sample, name: string, path = "", file1 = "", file2 = "", count = 0) =
    var files = 0
    s.name = name
    s.path = path
    s.file1 = file1
    s.file2 = file2
    s.count = count
    if len(file1) > 0:
      files += 1
    if len(file2) > 0:
      files += 1
    s.files = files 

proc `$`(a: sample): string =
  return $(a.name) & " -> (" & $(a.file1) & ";" & $(a.file2) & "): " & $(a.count) & " in " & $(a.files)

proc scanDirectory(dir: string, forTag = "_R1", revTag = "_R2", separator = "_", posList: seq[Value]): Table[string, sample] =
  #result = newTable[string, sample]()
  if dirExists(dir):
    let files = toSeq(walkDir(dir, relative=true))
    for f in files:
      if f.kind == pcFile:
        var sampleName : string
        for i in posList:
          let pos = parseInt($i)
          sampleName &= (f.path).split(separator)[pos - 1]

        if sampleName notin result:
          result[sampleName] = sample(path: dir, name: sampleName, count: 0, files: 0, file1: "", file2: "", flist : @[""])

        result[sampleName].flist.add(f.path)
        if forTag in f.path:
          result[sampleName].files += 1
          result[sampleName].file1 = f.path
        elif revTag in f.path:
          result[sampleName].files += 1
          result[sampleName].file2 = f.path
        else:
          result[sampleName].files += 1


proc countReads(filename: string): int =
  result = 0
  for rec in readfq(filename):
    result += 1

proc countReads(s: sample): sample =
  result = s
  result.count = countReads( joinPath(s.path, s.file1))

proc printLotus(samples: seq[sample]) =
  echo "#SampleID\tfastqFile"
  for s in samples:
    let files = if len(s.file2) > 0 : s.file1 & "," & s.file2
                else: s.file1
    echo s.name, "\t", files

proc printIrida(samples: seq[sample], p: int) =
  echo "[Data]"
  echo "Sample_Name,Project_ID,File_Forward,File_Reverse"
  for s in samples:
    echo s.name, ",", p, ",", s.file1, ",", s.file2

proc printQiime1(samples: seq[sample]) =

  # Qiime1 (compatible with 2): Header
  let headerCounts = if addCounts: "\tCounts"
                       else: ""

  let headerPath = if addPath: "\tPaths"
                     else: ""

  echo "#SampleID", headerCounts, headerPath

  # Qiime1 (compatible with 2): Samples
  for s in samples:
    let files = if (addPath and len(s.file2) > 0 ): "\t" & s.file1 & "," & s.file2
                elif addPath: "\t" & s.file1
                else: ""
    let counts = if addCounts: "\t" & $s.count
                 else: ""
    echo s.name, counts, files



proc printQiime2(samples: seq[sample]) =
  var
    secondLine  = "#q2:types"
    headerCounts = ""
    headerPath   = ""

  # Qiime1 (compatible with 2): Header
  if addCounts:
    headerCounts = "\tread-counts"
    secondLine   &= "\tnumeric"
  if addPath:
    headerPath = "\tread-paths"
    secondLine &= "\tcategorical"

  echo "sample-id", headerCounts, headerPath
  echo secondLine

  for s in samples:
    let files = if (addPath and len(s.file2) > 0 ): "\t" & s.file1 & "," & s.file2
                elif addPath: "\t" & s.file1
                else: ""
    let counts = if addCounts: "\t" & $s.count
                 else: ""
    echo s.name, counts, files



proc printManifest(samples: seq[sample]) =
  if isPe > 0:
    echo "sample-id", "\t", "forward-absolute-filepath", "\t", "reverse-absolute-filepath"
  else:
    echo "sample-id", "\t", "absolute-path"

  for s in samples:
    if isPe > 0:
      echo s.name, "\t", joinPath(s.path, s.file1), "\t", joinPath(s.path, s.file2)
    else:
      echo s.name, "\t", joinPath(s.path, s.file1)

proc printDadaist(samples: seq[sample]) =
  let headerCounts = if addCounts: "\tCounts"
                     else: ""


  echo "#SampleID", "\t", "Files", headerCounts
  for s in samples:
    let counts = if addCounts: "\t" & $s.count
                 else: ""
    let path = if isPe > 0: "\t" & joinPath(s.path, s.file1) & "," & joinPath(s.path, s.file2)
               else: "\t" & joinPath(s.path, s.file1)
    
    echo s.name, path, counts

proc printMetaphage(samples: seq[sample], splitStr = "_", pick = 0, defaultStr = "Cond") =
  let headerCounts = if addCounts: ",Counts"
                     else: ""


  echo "Sample", ",", "Treatment", ",", "Files", headerCounts
  for s in samples:
    var condition = defaultStr
    if splitStr in s.name:
      try:
        let splittedID = (s.name).split(splitStr)
        let part = if len(splittedID) > pick: splittedID[pick]
                  else: splittedID[0]
        condition = part
      except:
        condition = defaultStr
    else:
      condition = defaultStr

    let condStr = "," & condition
    let counts = if addCounts: "," & $s.count
                 else: ""
    let path = if isPe > 0: "," & joinPath(s.path, s.file1) & ";" & joinPath(s.path, s.file2)
               else: "," & joinPath(s.path, s.file1)
    
    echo s.name, condStr, path, counts

proc fastx_metadata(argv: var seq[string]): int =
    let validFormats = {
      "manifest": "qiime2 import manifest file",
      "qiime1": "Qiime1 mapping file",
      "qiime2": "Qiime2 metadata file",
      "dadaist": "Dadaist2 metadata file",
      "lotus": "lOTUs mappint file",
      "irida": "IRIDA uploader file",
      "metaphage": "Metaphage metadata file",
    }.toTable


    let args = docopt("""
Usage: metadata [options] [<dir>...]

Prepare mapping files from directory containing FASTQ files

Options:
  -1, --for-tag STR      String found in filename of forward reads [default: _R1]
  -2, --rev-tag STR      String found in filename of forward reads [default: _R2]
  -s, --split STR        Separator used in filename to identify the sample ID [default: _]
  --pos INT...           Which part of the filename is the Sample ID [default: 1]

  -f, --format TYPE      Output format: dadaist, irida, manifest, metaphage, qiime1, qiime2  [default: manifest]
  --pe                   Enforce paired-end reads (not supported)
  -p, --add-path         Add the reads absolute path as column 
  -c, --counts           Add the number of reads as a property column
  -t, --threads INT      Number of simultaneously opened files [default: 2]

  FORMAT SPECIFIC OPTIONS
  -P, --project INT      Project ID (only for irida)
  --meta-split STR       Separator in the SampleID to extract metadata, used in MetaPhage [default: _]
  --meta-part INT        Which part of the SampleID to extract metadata, used in MetaPhage [default: 1]
  --meta-default STR     Default value for metadata, used in MetaPhage [default: Cond]

  -v, --verbose          Verbose output
  -h, --help             Show this help

  """, version=version(), argv=argv)

    verbose = args["--verbose"]
     
    var
      outFmt: string
      forTag, revTag, splitString: string
      posList: seq[Value]
      threads: int
      projectID = 0
      metaDefault = $args["--meta-default"]
      metaSplit = $args["--meta-split"]
      metaPart  = 0
    try:
      projectID = if args["--project"]: parseInt($args["--project"])
                  else: 0
      metaPart = parseInt($args["--meta-part"]) - 1
      outFmt = $args["--format"]
      forTag = $args["--for-tag"]
      revTag = $args["--rev-tag"]
      splitString = $args["--split"]
      posList = @[args["--pos"]]
      threads = parseInt($args["--threads"])
      addCounts = args["--counts"]
      addPath   = args["--add-path"]
      enforcePe   = args["--pe"]
    except Exception as e:
      stderr.writeLine("Error: unexpected parameter value. ", e.msg)
      quit(1)
    
    setMaxPoolSize(threads)   

    var
      responses = newSeq[FlowVar[sample]]()
      samples = newSeq[sample]()
      peCount = 0
      seCount = 0
      skipCount = 0

    # Parameters validation: input dir
    if len(args["<dir>"]) == 0:
      stderr.writeLine("SeqFu metadata\nERROR: Specify (at least) one input directory. Use --help for more info.")
      quit(0)

    # Parameters validation: valid formats
    if outFmt notin validFormats:
      stderr.writeLine("SeqFu metadata\nERROR: Invalid format (", outFmt, "). Accepted formats:")
      for key, desc in validFormats.pairs:
        stderr.writeLine(" - ", key, " (", desc, ")")
      quit(1)

    # Parameters validation: --meta-part
    if metaPart < 0:
      stderr.writeLine("SeqFu metadata\nERROR: Invalid value for --meta-part. It must be > 1.")
      quit(1)

    for dir in args["<dir>"]:
      if not  dirExists(dir):
        stderr.writeLine("Error: input item '", dir, "' is not a directory: specify directory(ies) and not file(s).")
        quit(1)

      if verbose:
        stderr.writeLine("Processing directory: ", dir)
      
      let filesInPath = scanDirectory(dir.normalizedPath().absolutePath(), forTag, revTag, splitString, posList)
      for sample in filesInPath.values:
        if verbose:
          stderr.writeLine(" - Processing: ", sample.name)

        if sample.files > 2:
          stderr.writeLine("ERROR: Skipping sample '", sample.name, "' (",  sample.flist.join(" ") ,") has ", sample.files, " files (wrong sample id?)")
          if verbose:
            stderr.writeLine(sample)
          quit(1)
        elif sample.files == 1:
          seCount += 1
        elif sample.files == 2:
          peCount += 1

        if sample.file1 == "":
          if verbose:
            stderr.writeLine("WARNING: Skipping ", sample.name, ": no forward file found (", forTag, ")")
          skipCount += 1
          continue

        if sample.files == 2:
          isPe += 1
        else:
          isSe += 1

        if addCounts:
          let file1 = joinPath(dir, sample.file1)
          responses.add(spawn countReads(sample))
        else:
          samples.add(sample)

    
    if addCounts:
      for resp in responses:  
        let s = ^resp
        if verbose:
          stderr.writeLine("Counted reads for: ", s.name)
        samples.add(s)
    
    samples.sort do (x, y: sample) -> int:
      result = cmp(x.name, y.name)
      if result == 0:
          result = cmp(x.file1, y.file2)

    
    # Check samples collected
    if isPe > 0 and isSe > 0:
      stderr.writeLine("ERROR: Some samples have two files (paired-end) and other have only one.")
      quit(1)

    if len(samples) == 0:
      stderr.writeLine("Warning: no samples found")
      quit(0)

    # Print metadata/mapping file
    case outFmt:
      of "manifest":
        if args["--counts"]:
          stderr.writeLine("WARNING: Ignoring --counts as it's not supported by Manifest")
        if args["--add-path"]:
          stderr.writeLine("WARNING: Ignoring --add-path as it's not supported by Manifest")
        printManifest(samples)
      of "dadaist":
        printDadaist(samples)
      of "metaphage":
        printMetaphage(samples, metaSplit, metaPart, metaDefault)
      of "qiime1":
        printQiime1(samples)
      of "qiime2":
        printQiime2(samples)
      of "lotus":
        printLotus(samples)
      of "irida":
        if projectID == 0:
          stderr.writeLine("ERROR: Project ID not specified")
          quit(1)
        printIrida(samples, projectID)
      else:
        stderr.writeLine("ERROR:\nUnsupported output format: ", outFmt)
    

    