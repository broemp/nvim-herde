.PHONY: test demo
test:
	NVIM_LOG_FILE=/tmp/herde-tests-nvim.log nvim --headless -n -u NONE -i NONE -l tests/run.lua
	PYTHONDONTWRITEBYTECODE=1 python3 tests/install.py
demo:
	nvim -u NONE -i NONE --cmd 'set rtp+=.' -c 'lua require("herde").setup({backend="demo"})' -c 'Herde toggle'
