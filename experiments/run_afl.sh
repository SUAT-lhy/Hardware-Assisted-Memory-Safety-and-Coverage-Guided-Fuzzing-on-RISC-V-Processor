rm -rf ~/hast_rv/afl_out
timeout 48 afl-fuzz -i ~/hast_rv/seeds -o ~/hast_rv/afl_out -- ~/hast_rv/bin/vuln_afl @@ >/dev/null 2>&1
cat ~/hast_rv/afl_out/default/fuzzer_stats