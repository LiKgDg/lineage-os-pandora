# Xiaomi 17 Pro (pandora / canoe / Qualcomm SM8850) device tree
#
#   make            Build all DTB/DTBO artifacts from dts/ into build/
#   make merge      Merge stock base dtb + board overlay with fdtoverlay
#   make extract    Extract dtbo/vendor_boot from stock OTA + PixelOS, rebuild
#                   original/manifest.tsv
#   make verify     Rebuild and verify against the shipped stock blobs
#   make clean      Remove build output
#
# Requirements: device-tree-compiler (dtc >= 1.6), python3. No kernel tree is
# required to rebuild these DTS because the decompiled constants are inlined.
# On Windows/Git Bash the recipes are forwarded to WSL by scripts/in-wsl.sh.
DTC       ?= dtc
PYTHON    ?= python3
PAGE_SIZE ?= 4096
OUT       := build
RUN       := bash scripts/in-wsl.sh

# 可覆盖的输入源（留空则用脚本内的默认路径）
STOCK_OTA   ?=
PIXELOS_ZIP ?=
WORK_DIR    ?=
STOCK_DTBO  ?=
PIXELOS_DTBO ?=
LOS_DTBO    ?=

.PHONY: all dtb merge extract verify clean help

all: dtb

dtb:
	@$(RUN) env PAGE_SIZE="$(PAGE_SIZE)" bash scripts/build-dtb.sh

merge: dtb
	@$(RUN) bash scripts/merge-dtb.sh

extract:
	@STOCK_OTA="$(STOCK_OTA)" PIXELOS_ZIP="$(PIXELOS_ZIP)" WORK_DIR="$(WORK_DIR)" \
	  $(RUN) bash scripts/extract-dt.sh

verify:
	@WORK_DIR="$(WORK_DIR)" STOCK_DTBO="$(STOCK_DTBO)" \
	  PIXELOS_DTBO="$(PIXELOS_DTBO)" LOS_DTBO="$(LOS_DTBO)" \
	  $(RUN) bash scripts/verify-stock.sh

clean:
	rm -rf "$(OUT)"

help:
	@echo "make / make dtb   compile dts/*.dts(.dtsi) and overlays into $(OUT)/"
	@echo "make merge        fdtoverlay base+overlay and reconcile with $(OUT)/xiaomi-pandora.dtb"
	@echo "make extract      extract dtbo/vendor_boot from stock OTA + PixelOS, write original/manifest.tsv"
	@echo "make verify       rebuild and deep-verify root props, dtbo.img entries, 3-source matrix"
	@echo "make clean        remove $(OUT)/"
