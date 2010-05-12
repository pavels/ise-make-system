#-------------------------------------------------------------------
# Company       : XESS Corp.
# Engineer      : Dave Vanden Bout
# Creation Date : 05/16/2006
# Copyright     : 2005-2006, XESS Corp
# Tool Versions : make 3.79.1, perl 5.8.8, WebPACK 8.1.03i
#
# Description:
#    This makefile contains the rules that move the HDL files through
#    the Xilinx WebPACK/ISE synthesizer, place & route and bitstream 
#    generation processes to produce the final bitstream file.
#
# Revision:
#    1.0.3
#
# Additional Comments:
#    This file is normally included in another makefile using the
#    `include' directive.  Usually this file is placed in the 
#    /usr/local/include directory so make can find it automatically.
#
#    The makefile targets are:
#        config: Creates bit/svf file for FPGA
#        svf:    Directly creates bit file for FPGA.
#        mcs:    Creates Intel MCS file from bit file.
#        exo:    Creates Motorola EXO file from bit file.
#        timing: Creates timing report for FPGA.
#        clean:  Cleans temporary files created during build process.
#        distclean: Clean and also remove timing report.
#        maintainer-clean: Distclean and also remove bit/svf files.
#        nice:   beautify the HDL source code
#
#    1.0.4: Modified for ISE10 - remved CPLD support because it is broken
#           Added .prj autogeneration (see example Makefile for project)
#           Added .xst .ut and .ucf templates autocopy
#           Only things needed now is .vhd files and Makefile
#
#    1.0.3:
#        Modified to support ISE9 project directory structure.
#    1.0.2:
#        Added more file types for removal during cleaning.
#    1.0.1:
#        Added 'nice' target.
#    1.0.0
#        Initial revision.
#-------------------------------------------------------------------



#
# Paths to utilities.
#

# Standard OS utilities.  These are for DOS.  Set them for your particular OS.
RM                 := rm -f
RMDIR              := rm -f -r
MKDIR              := mkdir
ECHO               := echo
EMACS              := emacs

# These are Perl script files that perform some simple operations.
UTILITY_DIR        := ~/ise/make-system/
SET_OPTION_VALUES  := perl $(UTILITY_DIR)set_option_values.pl
GET_OPTION_VALUES  := perl $(UTILITY_DIR)get_option_values.pl
GET_PROJECT_FILES  := perl $(UTILITY_DIR)get_project_files.pl



#
# Flags and option values that control the behavior of the Xilinx tools.
# You can override these values in the makefile that includes this one.
# Otherwise, the default values will be set as shown below.
#

# Unless otherwise specified, the name of the design and the top-level
# entity are derived from the name of the directory that contains the design.
DIR_SPACES  := $(subst /, ,$(CURDIR))
DIR_NAME    := $(word $(words $(DIR_SPACES)), $(DIR_SPACES))
DESIGN_NAME ?= $(DIR_NAME)
TOP_NAME    ?= $(DESIGN_NAME)
SYNTH_DIR   ?= .
SIM_DIR   ?= .

# Extract the part identifier from the project .npl file.
PART_TYPE        ?=            $(shell $(GET_OPTION_VALUES) $(DESIGN_NAME).npl DEVICE)
PART_SPEED_GRADE ?= $(subst -,,$(shell $(GET_OPTION_VALUES) $(DESIGN_NAME).npl DEVSPEED))
PART_PACKAGE     ?=            $(shell $(GET_OPTION_VALUES) $(DESIGN_NAME).npl DEVPKG)
PART             ?= $(PART_TYPE)-$(PART_SPEED_GRADE)-$(PART_PACKAGE)

# Flags common to both FPGA design flow.
INTSTYLE         ?= -intstyle silent      # call Xilinx tools in silent mode
XST_FLAGS        ?= $(INTSTYLE)           # most synthesis flags are specified in the .xst file
UCF_FILE         ?= $(DESIGN_NAME).ucf    # constraint/pin-assignment file
NGDBUILD_FLAGS   ?= $(INTSTYLE) -dd _ngo  # ngdbuild flags
NGDBUILD_FLAGS += $(if $(UCF_FILE),-uc,) $(UCF_FILE)         # append the UCF file option if it is specified 

# Flags for FPGA-specific tools.  These were extracted by looking in the
# .cmd_log file after compiling the design with the WebPACK/ISE GUI.
MAP_FLAGS        ?= $(INTSTYLE) -cm area -pr b -c 100 -tx off
PAR_FLAGS        ?= $(INTSTYLE) -w -ol std -t 1
TRCE_FLAGS       ?= $(INTSTYLE) -e 3 -l 3
BITGEN_FLAGS     ?= $(INTSTYLE) -w        # most bitgen flags are specified in the .ut file
PROMGEN_FLAGS    ?= -u 0                  # flags that control the MCS/EXO file generation

# Determine the version of Xilinx ISE that is being used by reading it from the
# readme.txt file in the top-level directory of the Xilinx software.
PROJNAV_DIR ?= .

XST_FPGA_OPTIONS_FILE ?= $(PROJNAV_DIR)/$(DESIGN_NAME).xst
BITGEN_OPTIONS_FILE   ?= $(DESIGN_NAME).ut
XST_OPTIONS_FILE       = $(XST_FPGA_OPTIONS_FILE)



#
# The following rules describe how to compile the design to an FPGA
#

HDL_FILES := $(foreach file,$(SRCS_SYNTH),$(SYNTH_DIR)/$(file))
SIM_FILES := $(foreach file,$(SRCS_SIM),$(SIM_DIR)/$(file))

# default target
all: bit


# cleanup the source code to make it look nice
%.nice: %.vhd
	$(EMACS) -batch $< -f vhdl-beautify-buffer -f save-buffer
	$(RM) $<~

#PRJ FIle generation
%.prj:
	rm -f  $(DESIGN_NAME).prj;
	for file in $(HDL_FILES); do \
	echo "vhdl work $${file}" >> $(DESIGN_NAME).prj ; \
	done ;

%.ut:
	cp -n $(UTILITY_DIR)/default.ut $(DESIGN_NAME).ut

%.xst:
	cp -n $(UTILITY_DIR)/default.xst $(DESIGN_NAME).xst

%.ucf:
	cp -n $(UTILITY_DIR)/default.ucf $(UCF_FILE)

# Synthesize the HDL files into an NGC file.  This rule is triggered if
# any of the HDL files are changed or the synthesis options are changed.
%.ngc: $(HDL_FILES) $(XST_OPTIONS_FILE) $(DESIGN_NAME).prj $(DESIGN_NAME).ut
	$(SET_OPTION_VALUES) $(XST_OPTIONS_FILE) \
		"set -tmpdir $(PROJNAV_DIR)" \
		"-lso $(DESIGN_NAME).lso" \
		"-ifn $(DESIGN_NAME).prj" \
		"-ofn $(DESIGN_NAME)" \
		"-p $(PART)" \
		"-top $(TOP_NAME)" \
			> $(PROJNAV_DIR)/tmp.xst
	xst $(XST_FLAGS) -ifn $(PROJNAV_DIR)/tmp.xst -ofn $*.syr

# Take the output of the synthesizer and create the NGD file.  This rule
# will also be triggered if constraints file is changed.
%.ngd: %.ngc %.ucf
	ngdbuild $(NGDBUILD_FLAGS) -p $(PART) $*.ngc $*.ngd

# Map the NGD file and physical-constraints to the FPGA to create the mapped NCD file.
%_map.ncd %.pcf: %.ngd
	map $(MAP_FLAGS) -p $(PART) -o $*_map.ncd $*.ngd $*.pcf

# Place & route the mapped NCD file to create the final NCD file.
%.ncd: %_map.ncd %.pcf
	par $(PAR_FLAGS) $*_map.ncd $*.ncd $*.pcf

# Take the final NCD file and create an FPGA bitstream file.  This rule will also be
# triggered if the bit generation options file is changed.
%.bit: %.ncd $(BITGEN_OPTIONS_FILE)
	bitgen $(BITGEN_FLAGS) -f $(BITGEN_OPTIONS_FILE) $*.ncd

# Convert a bitstream file into an MCS hex file that can be stored into Flash memory.
%.mcs: %.bit
	promgen $(PROMGEN_FLAGS) $*.bit -p mcs

# Convert a bitstream file into an EXO hex file that can be stored into Flash memory.
%.exo: %.bit
	promgen $(PROMGEN_FLAGS) $*.bit -p exo

# Use .config suffix to trigger creation of a bit/svf file
# depending upon whether an FPGA is the target device.
%.config: %.bit ;

# Create the FPGA timing report after place & route.
%.twr: %.ncd %.pcf
	trce $(TRCE_FLAGS) $*.ncd -o $*.twr $*.pcf

# Use .timing suffix to trigger timing report creation.
%.timing: %.twr ;

# Preserve intermediate files.
.PRECIOUS: %.ngc %.ngd %_map.ncd %.ncd %.twr %.vm6 %.jed %.prj %.ut %.xst %.ucf

# Clean up after creating the configuration file.
%.clean:
	-$(RM) *.stx *.ucf.untf *.mrp *.nc1 *.ngm *.prm *.lfp
	-$(RM) *.placed_ncd_tracker *.routed_ncd_tracker
	-$(RM) *.pad_txt *.twx *.log *.vhd~ *.dhp *.jhd *.cel
	-$(RM) *.ngr *.ngc *.ngd *.syr *.bld *.pcf
	-$(RM) *_map.mrp *_map.ncd *_map.ngm *.ncd *.pad *.bit
	-$(RM) *.par *.xpi *_pad.csv *_pad.txt *.drc *.bgn *.lso *.npl
	-$(RM) *.xml *_build.xml *.rpt *.gyd *.mfd *.pnx *.xrpt *.ptwx *.twr *.srp
	-$(RM) *.vm6 *.jed *.err *.ER result.txt tmperr.err *.bak *.vhd~
	-$(RM) *.zip *_backup *.*log *.map *.unroutes *.html
	-$(RM) impactcmd.txt tmp.xst impact.run *.wlf transcript
	-$(RMDIR) xst _ngo *_html __projnav xlnx_auto_* work

# Clean everything.
%.distclean: %.clean
	-$(RM) *.prj

%.impact : $(DESIGN_NAME).bit
	echo -e "setMode -bs \n\
	setCable -p auto \n\
	identify  \n\
	assignFile -p 1 -file $(DESIGN_NAME).bit \n\
	program -p 1 \n\
	quit \n" > impact.run
	impact -batch impact.run

#Simulation using ModelSIM
setlib:
	vlib work

vsim-compile: setlib $(SIM_FILES) $(HDL_FILES)
	vcom $(HDL_FILES)  $(SIM_FILES)

vsim: vsim-compile
	vsim  $(TESTBENCH_NAME)

vsim-run: vsim-compile
	vsim -c -do "run -all; quit" $(TESTBENCH_NAME)

#
# Default targets for FPGA compilations.
#

config          : $(DESIGN_NAME).config
bit             : $(DESIGN_NAME).bit
mcs             : $(DESIGN_NAME).mcs
exo             : $(DESIGN_NAME).exo
timing          : $(DESIGN_NAME).timing
clean           : $(DESIGN_NAME).clean
distclean       : $(DESIGN_NAME).distclean
nice            : $(subst .vhd,.nice,$(HDL_FILES))
impact          : $(DESIGN_NAME).impact
