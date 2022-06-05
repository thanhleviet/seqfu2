
# Create "make test"
.PHONY: test clean build

BIN=./bin
SOURCE=./src
DATA=./data
VERSION := $(shell grep version seqfu.nimble  | grep  -o "[0-9]\\+\.[0-9]\\+\.[0-9]\\+")
NIMPARAM :=  --gc:arc -d:NimblePkgVersion=$(VERSION) -d:release --opt:speed 
TARGETS=$(BIN)/seqfu $(BIN)/fu-msa $(BIN)/fu-primers $(BIN)/dadaist2-mergeseqs $(BIN)/fu-shred $(BIN)/fu-homocomp $(BIN)/fu-multirelabel $(BIN)/fu-index $(BIN)/fu-cov $(BIN)/fu-16Sregion  $(BIN)/fu-nanotags  $(BIN)/fu-orf  $(BIN)/fu-sw  $(BIN)/fu-virfilter  $(BIN)/fu-tabcheck  $(BIN)/fu-homocomp 

all: $(TARGETS)

src/sfu.nim: ./src/fast*.nim ./src/*utils*.nim
	touch $@ 

$(BIN)/seqfu: src/sfu.nim
	nim c $(NIMPARAM) --out:$@ $<

$(BIN)/fu-primers: src/fu_primers.nim
	nim c $(NIMPARAM) --out:$@ $<

$(BIN)/fu-shred: src/fu_shred.nim
	nim c $(NIMPARAM) --out:$@ $<

$(BIN)/fu-nanotags: src/fu_nanotags.nim
	nim c $(NIMPARAM) --out:$@ $<

$(BIN)/fu-orf: src/fu_orf.nim
	nim c $(NIMPARAM) --out:$@ $<

$(BIN)/fu-sw: src/fu_sw.nim
	nim c $(NIMPARAM) --out:$@ $<

$(BIN)/fu-homocomp: src/fu_homocomp.nim
	nim c $(NIMPARAM) --out:$@ $<

$(BIN)/fu-multirelabel: src/fu_multirelabel.nim
	nim c $(NIMPARAM) --out:$@ $<

$(BIN)/fu-index: src/fu_index.nim
	nim c $(NIMPARAM) --out:$@ $<

$(BIN)/fu-cov: src/fu_cov.nim
	nim c $(NIMPARAM) --out:$@ $<

$(BIN)/fu-msa: src/fu_msa.nim
	nim c $(NIMPARAM) --out:$@ $<

$(BIN)/fu-virfilter: src/fu_virfilter.nim
	nim c $(NIMPARAM) --out:$@ $<

$(BIN)/fu-tabcheck: src/fu_tabcheck.nim
	nim c $(NIMPARAM) --out:$@ $<

$(BIN)/fu-16Sregion: src/dadaist2_region.nim
	nim c $(NIMPARAM) --out:$@ $<

$(BIN)/dadaist2-mergeseqs: src/dadaist2_mergeseqs.nim
	nim c $(NIMPARAM) --out:$@ $<

multiqc: $(BIN)/seqfu
	mkdir -p temp-mqc
	$(BIN)/seqfu stats $(DATA)/filt.fa.gz $(DATA)/orf.fa.gz --multiqc temp-mqc/stats_mqc.txt
	multiqc -f -o multiqc/ temp-mqc
	rm -rf temp-mqc
	open "multiqc/multiqc_report.html"
	
build:
	nimble build

test:
	bash ./test/mini.sh

clean:
	@echo "Cleaning..."
	@for i in $(TARGETS); \
	do \
		if [ -e "$$i" ]; then rm -f $$i; echo "Removing $$i"; else echo "$$i Not found"; fi \
	done
