# ============================
# Makefile com rebuild da imagem + correções de permissão
# ============================

SHELL := /bin/bash

# --- Imagens
DOCKER_IMAGE         := aignacio/nox:latest
DOCKER_RISCOF_IMAGE  := aignacio/riscof

# --- UID/GID do host para escrever artefatos com o seu usuário
DOCKER_UID := $(shell id -u)
DOCKER_GID := $(shell id -g)

# --- Containers
DOCKER_CONTAINER_BUILD := ship_nox
DOCKER_CONTAINER_SW    := sw_nox

# --- docker run como ROOT (para limpar arquivos antigos root-owned)
RUN_CMD_ROOT := docker run --rm --name $(DOCKER_CONTAINER_BUILD) \
                -v $(abspath .):/nox_files -w /nox_files $(DOCKER_IMAGE)

# --- docker run como USUÁRIO DO HOST (para compilar e gerar artefatos com dono correto)
RUN_CMD_USER := docker run --rm --name $(DOCKER_CONTAINER_BUILD) \
                -u $(DOCKER_UID):$(DOCKER_GID) \
                -v $(abspath .):/nox_files -w /nox_files $(DOCKER_IMAGE)

RUN_CMD_COMP := docker run --rm --name $(DOCKER_CONTAINER_BUILD) \
                -v $(abspath .):/test -w /test/riscof_compliance $(DOCKER_RISCOF_IMAGE)

# ============================
# Configs do design
# ============================
AXI_IF             ?= 1
GTKWAVE_PRE        := /Applications/gtkwave.app/Contents/Resources/bin/

# Design files
_SRC_VERILOG ?=  bus_arch_sv_pkg/amba_axi_pkg.sv
_SRC_VERILOG +=  bus_arch_sv_pkg/amba_ahb_pkg.sv
_SRC_VERILOG +=  rtl/inc/nox_pkg.svh
_SRC_VERILOG +=  rtl/inc/core_bus_pkg.svh
_SRC_VERILOG +=  rtl/inc/riscv_pkg.svh
_SRC_VERILOG +=  rtl/inc/nox_utils_pkg.sv
_SRC_VERILOG +=  $(shell find rtl/ -type f -iname *.sv)
_CORE_VERILOG :=  $(_SRC_VERILOG)
_SRC_VERILOG +=  $(shell find tb/  -type f -iname *.sv)
SRC_VERILOG  ?=  $(_SRC_VERILOG)

# SoC design files
_SOC_VERILOG  +=  bus_arch_sv_pkg/amba_axi_pkg.sv
_SOC_VERILOG  +=  bus_arch_sv_pkg/amba_ahb_pkg.sv
_SOC_VERILOG  +=  rtl/inc/nox_pkg.svh
_SOC_VERILOG  +=  rtl/inc/core_bus_pkg.svh
_SOC_VERILOG  +=  rtl/inc/riscv_pkg.svh
_SOC_VERILOG  +=  rtl/inc/nox_utils_pkg.sv
_SOC_VERILOG  +=  tb/axi_mem.sv
_SOC_VERILOG  +=  $(_CORE_VERILOG)
_SOC_VERILOG  +=  $(shell find xlnx/rtl/verilog-axi/rtl -type f -iname *.v)
_SOC_VERILOG  +=  xlnx/rtl/wbuart32/rtl/axiluart.v
_SOC_VERILOG  +=  xlnx/rtl/wbuart32/rtl/rxuart.v
_SOC_VERILOG  +=  xlnx/rtl/wbuart32/rtl/rxuartlite.v
_SOC_VERILOG  +=  xlnx/rtl/wbuart32/rtl/skidbuffer.v
_SOC_VERILOG  +=  xlnx/rtl/wbuart32/rtl/txuart.v
_SOC_VERILOG  +=  xlnx/rtl/wbuart32/rtl/txuartlite.v
_SOC_VERILOG  +=  xlnx/rtl/wbuart32/rtl/ufifo.v
_SOC_VERILOG  +=  xlnx/rtl/axi_interconnect_wrapper.sv
_SOC_VERILOG  +=  xlnx/rtl/axi_mem_wrapper.sv
_SOC_VERILOG  +=  xlnx/rtl/axi_rom_wrapper.sv
_SOC_VERILOG  +=  xlnx/rtl/axi_uart_wrapper.sv
_SOC_VERILOG  +=  xlnx/rtl/axi_crossbar_wrapper.sv
_SOC_VERILOG  +=  xlnx/rtl/cdc_2ff_sync.sv
_SOC_VERILOG  +=  xlnx/rtl/clk_mgmt.sv
_SOC_VERILOG  +=  xlnx/rtl/rst_ctrl.sv
_SOC_VERILOG  +=  xlnx/rtl/axi_gpio.sv
_SOC_VERILOG  +=  xlnx/rtl/nox_wrapper.sv
_SOC_VERILOG  +=  xlnx/rtl/cdc_async_fifo.sv
_SOC_VERILOG  +=  xlnx/rtl/axi_spi_master.sv
_SOC_VERILOG  +=  xlnx/rtl/axi_mtimer.sv
_SOC_VERILOG  +=  sw/bootloader/output/boot_rom.sv

ifeq ($(AXI_IF),0)
  _SOC_VERILOG  +=  xlnx/rtl/nox_soc_ahb.sv
else
  _SOC_VERILOG  +=  xlnx/rtl/nox_soc.sv
endif
SOC_VERILOG := $(_SOC_VERILOG)

# Includes
_INCS_VLOG  ?= rtl/inc
INCS_VLOG   := $(addprefix -I,$(_INCS_VLOG))

# Params
IRAM_KB_SIZE ?= 128
DRAM_KB_SIZE ?= 32
ENTRY_ADDR   ?= \'h8000_0000
IRAM_ADDR    ?= 0x80000000
DRAM_ADDR    ?= 0x10000000
IRAM_ADDR_SOC ?= 0xa0000000
DRAM_ADDR_SOC ?= 0x10000000
DISPLAY_TEST  ?= 0
WAVEFORM_USE  ?= 1

# Verilator info
VERILATOR_TB   := tb
WAVEFORM_FST   ?= nox_waves.fst
OUT_VERILATOR  := output_verilator
ROOT_MOD_VERI  := nox_sim
ROOT_MOD_SOC   := nox_soc
VERILATOR_EXE  := $(OUT_VERILATOR)/$(ROOT_MOD_VERI)
VERI_EXE_SOC   := $(OUT_VERILATOR)/$(ROOT_MOD_SOC)

# Testbench files
SRC_CPP       := $(wildcard $(VERILATOR_TB)/cpp/testbench.cpp)
SRC_CPP_SOC   := $(wildcard $(VERILATOR_TB)/cpp/testbench_soc.cpp)
_INC_CPPS     := ../tb/cpp/elfio
_INC_CPPS     += ../tb/cpp/inc
INCS_CPP      := $(addprefix -I,$(_INC_CPPS))

# Macros SV
_MACROS_VLOG  ?= IRAM_KB_SIZE=$(IRAM_KB_SIZE)
_MACROS_VLOG  += DRAM_KB_SIZE=$(DRAM_KB_SIZE)
_MACROS_VLOG  += ENTRY_ADDR=$(ENTRY_ADDR)
_MACROS_VLOG  += DISPLAY_TEST=$(DISPLAY_TEST)
_MACROS_VLOG  += SIMULATION
ifeq ($(RV_COMPLIANCE),1)
  _MACROS_VLOG += RV_COMPLIANCE
else
  _MACROS_VLOG += EN_PRINTF
endif

ifeq ($(AXI_IF),0)
  _MACROS_VLOG += TARGET_IF_AHB
else
  _MACROS_VLOG += TARGET_IF_AXI
endif
MACROS_VLOG   ?= $(addprefix +define+,$(_MACROS_VLOG))

# CFLAGS p/ wrapper C++ do Verilator
CPPFLAGS_VERI := "$(INCS_CPP) -O0 -g3 -Wall -Werror \
                  -DIRAM_KB_SIZE=\"$(IRAM_KB_SIZE)\" \
                  -DDRAM_KB_SIZE=\"$(DRAM_KB_SIZE)\" \
                  -DIRAM_ADDR=\"$(IRAM_ADDR)\" \
                  -DDRAM_ADDR=\"$(DRAM_ADDR)\" \
                  -DWAVEFORM_USE=\"$(WAVEFORM_USE)\" \
                  -DWAVEFORM_FST=\"$(WAVEFORM_FST)\""

CPPFLAGS_SOC  := "$(INCS_CPP) -O0 -g3 -Wall \
                  -DIRAM_KB_SIZE=\"$(IRAM_KB_SIZE)\" \
                  -DDRAM_KB_SIZE=\"$(DRAM_KB_SIZE)\" \
                  -DIRAM_ADDR=\"$(IRAM_ADDR_SOC)\" \
                  -DDRAM_ADDR=\"$(DRAM_ADDR_SOC)\" \
                  -DWAVEFORM_USE=\"$(WAVEFORM_USE)\" \
                  -DWAVEFORM_FST=\"$(WAVEFORM_FST)\""

# Evita travar por redefinição de macro (TARGET_IF_*)
VERILATOR_OPTS ?= --Wno-DEFOVERRIDE

VERIL_ARGS := -CFLAGS $(CPPFLAGS_VERI) \
              --top-module $(ROOT_MOD_VERI) \
              --Mdir $(OUT_VERILATOR) \
              -f verilator.flags \
              $(VERILATOR_OPTS) \
              $(INCS_VLOG) \
              $(MACROS_VLOG) \
              $(SRC_VERILOG) \
              $(SRC_CPP) \
              -o $(ROOT_MOD_VERI)

VERIL_ARGS_SOC := -CFLAGS $(CPPFLAGS_SOC) \
                  --top-module $(ROOT_MOD_SOC) \
                  --Mdir $(OUT_VERILATOR) \
                  -f verilator.flags \
                  $(VERILATOR_OPTS) \
                  $(INCS_VLOG) \
                  $(MACROS_VLOG) \
                  $(SOC_VERILOG) \
                  $(SRC_CPP_SOC) \
                  -o $(ROOT_MOD_SOC)

# ============================
# Alvos
# ============================
.PHONY: help lint clean clean_root all run conv_verilog wave soc run_soc \
        build_nox_docker docker_clean docker_prune docker_rebuild \
        build_comp run_comp wave_soc

help:
	@echo "Targets:"
	@echo "  docker_rebuild - Limpa containers/imagens e reconstrói a imagem $(DOCKER_IMAGE) sem cache"
	@echo "  all            - Rebuild da imagem + build do simulador nox (verilator)"
	@echo "  run            - Roda sw/hello_world no simulador"
	@echo "  soc            - Rebuild da imagem + build do SoC (verilator)"
	@echo "  run_soc        - Roda sw/soc_hello_world no simulador"
	@echo "  lint           - Lint com Verilator"
	@echo "  wave           - Abre GTKWave (core)"
	@echo "  wave_soc       - Abre GTKWave (SoC)"
	@echo "  clean          - Limpa artefatos (como root no container, evita erro de permissão)"
	@echo "  build_comp     - Build p/ compliance (RV_COMPLIANCE=1)"
	@echo "  run_comp       - Executa compliance"

# --- Limpa containers antigos
docker_clean:
	-@docker rm -f $(DOCKER_CONTAINER_BUILD) 2>/dev/null || true
	-@docker rm -f $(DOCKER_CONTAINER_SW)    2>/dev/null || true

# --- Limpa imagens e cache
docker_prune:
	-@docker image ls -q $(DOCKER_IMAGE) | xargs -r docker rmi -f
	-@docker image prune -f
	-@docker builder prune -f

# --- Rebuild SEMPRE da imagem (no-cache)
build_nox_docker: docker_clean docker_prune
	@echo "==> Building fresh $(DOCKER_IMAGE) (no cache)"
	@DOCKER_BUILDKIT=1 docker build --no-cache -f Dockerfile.nox -t $(DOCKER_IMAGE) .

docker_rebuild: build_nox_docker

# --- Limpeza de artefatos como ROOT (resolve 'Permissão recusada')
clean_root:
	-@$(RUN_CMD_ROOT) bash -lc 'rm -rf output_verilator nox_waves.fst'

# --- (Mantém um clean "host", mas chamando o root do container)
clean: clean_root
	@true

# --- Conversão SV->V (usa usuário do host para não criar arquivos root)
conv_verilog:
	$(RUN_CMD_USER) sv2v $(INCS_VLOG) $(_CORE_VERILOG) > design.v

wave: $(WAVEFORM_FST)
	$(GTKWAVE_PRE)gtkwave $(WAVEFORM_FST) waves.gtkw

lint: $(SRC_VERILOG) $(SRC_CPP) $(TB_VERILATOR)
	$(RUN_CMD_USER) verilator --lint-only $(VERIL_ARGS)

# --- ALWAYS rebuild image antes de compilar (como você pediu)
all: docker_rebuild clean $(VERILATOR_EXE)
	@echo ""
	@echo "Design build done, run as follows:"
	@echo "$(VERILATOR_EXE) -h"
	@echo ""

# --- SW hello world
RUN_SW := sw/hello_world/output/hello_world.elf
$(RUN_SW):
	make -C sw/hello_world all

run: $(RUN_SW)
	$(RUN_CMD_USER) ./$(VERILATOR_EXE) -s 100000 -e $<

$(VERILATOR_EXE): $(OUT_VERILATOR)/V$(ROOT_MOD_VERI).mk
	$(RUN_CMD_USER) make -C $(OUT_VERILATOR) -f V$(ROOT_MOD_VERI).mk

$(OUT_VERILATOR)/V$(ROOT_MOD_VERI).mk: $(SRC_VERILOG) $(SRC_CPP) $(TB_VERILATOR)
	$(RUN_CMD_USER) verilator $(VERIL_ARGS)

# --- SoC
wave_soc: $(WAVEFORM_FST)
	$(GTKWAVE_PRE)gtkwave $(WAVEFORM_FST) waves_soc.gtkw

$(VERI_EXE_SOC): $(OUT_VERILATOR)/V$(ROOT_MOD_SOC).mk
	$(RUN_CMD_USER) make -C $(OUT_VERILATOR) -f V$(ROOT_MOD_SOC).mk

$(OUT_VERILATOR)/V$(ROOT_MOD_SOC).mk: $(SOC_VERILOG) $(SRC_CPP_SOC) $(TB_VERILATOR)
	$(RUN_CMD_USER) verilator $(VERIL_ARGS_SOC)

soc: docker_rebuild clean $(VERI_EXE_SOC)
	@echo ""
	@echo "Design build done, run as follows:"
	@echo "$(VERI_EXE_SOC) -h"
	@echo ""

# --- Compliance
build_comp:
	make all RV_COMPLIANCE=1 IRAM_ADDR=0x80000000 DRAM_ADDR=0x10000000 IRAM_KB_SIZE=2048 DRAM_KB_SIZE=128 WAVEFORM_USE=0

run_comp:
	$(RUN_CMD_COMP) riscof --verbose info arch-test --clone
	$(RUN_CMD_COMP) riscof validateyaml --config=config.ini
	$(RUN_CMD_COMP) riscof testlist --config=config.ini --suite=riscv-arch-test/riscv-test-suite/ --env=riscv-arch-test/riscv-test-suite/env
	$(RUN_CMD_COMP) riscof run --config=config.ini --suite=riscv-arch-test/riscv-test-suite/ --env=riscv-arch-test/riscv-test-suite/env

