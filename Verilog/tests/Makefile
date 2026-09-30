# Meta-checks over the test suite itself.
#
# test-tb-catalog: every testbench in the tree is either reached by
# run_all_tests.sh or explicitly baselined in tb_catalog.py with a reason.
# Catches the drift where a testbench is written, works, and is then never
# run again because nobody added it to the registry.

test-tb-catalog:
	python3 tb_catalog.py --check

# test-docs-check: every relative link in every tracked *.md resolves.
# Born 28-AUG-2026 from the DEVELOPMENT.md/HARDWARE.md incident: the README
# pointed at the repo root for five months while the files sat in tmp/.
test-docs-check:
	python3 check_md_links.py

# test-no-machine-paths: no tracked text file names a path that is right on
# one machine only (a drive letter into a real folder, /mnt/<drive>/...,
# /<drive>/Dev/..., a home directory). Born 30-SEP-2026 when ~140 files held
# such paths; paths inside the repo are derived at run time, paths outside it
# are environment variables (ND_REPOS, ND120_<WHAT> - see CONTRIBUTING.md).
test-no-machine-paths:
	python3 check_no_machine_paths.py

# test-microcode-sync: every copy of the microcode PROM images matches
# Code/Microcode/ (dated exceptions only). Catches the 895f360 trap where
# sims validated different microcode than the boards ran for 8 months.
test-microcode-sync:
	python3 microcode_sync.py

catalog:
	python3 tb_catalog.py

.PHONY: test-tb-catalog test-microcode-sync test-docs-check test-no-machine-paths catalog

# The silicon path must be flip-flop mode on every board - see
# check_no_latches.sh for why this is a check and not a remembered rule.
.PHONY: test-no-latches
test-no-latches:
	@./check_no_latches.sh
