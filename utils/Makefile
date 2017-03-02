.DEFAULT_GOAL := facters
default: facters ;

KBSRC  = raw_data_from_KB.txt
JSON = ../build_numbers/esxi_build_numbers.json

build_numbers: 
	@cat $(KBSRC) | ./create_esxi_build_numbers_json.pl > $(JSON)

# If you want to report on 6.0u2 instead of 6.0, you can.  Add option --minor here.
facters: build_numbers
	$(foreach file, $(wildcard templates/*) , @./matchup-bios-to-string.pl --template $(file) > ../lib/facter/$(notdir $(file))  )

clean:
	@if [ ! -f $(KBSRC) ]; then \
		echo "Not removing $(JSON) as you do not have a source $(KBSRC) to rebuild from."; \
	else \
		rm -f $(JSON);\
	fi
	rm -f ../lib/facter/*

.PHONY: build_numbers facters clean default
