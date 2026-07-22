# Tests

`merge.test.sh` — pure unit, no network.
`fetch.test.sh` — hits live company sites; may flake if a site is down. Rerun once before investigating failures.

Run all: `bash tests/merge.test.sh && bash tests/fetch.test.sh`
