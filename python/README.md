# AquaVol mathematical reference

This package is an independent reference for the AquaVol pricing specification.
It uses only the Python standard library and is not part of the live transaction
path.

Run the tests from the repository root:

```bash
PYTHONPATH=python python3 -m unittest discover -s python/tests -v
```

Regenerate the canonical vector document:

```bash
PYTHONPATH=python python3 -m aquavol_math.generate_vectors
```

Print the exact integer inventory-settlement vectors:

```bash
PYTHONPATH=python python3 -m aquavol_math.generate_inventory_vectors
```

The generator prints JSON to standard output. Compare it with
`test/vectors/black_scholes-v1.json` or
`test/vectors/inventory_settlement-v1.json`, as appropriate; do not replace a
committed vector file without reviewing the numerical change and updating its
schema or model version when appropriate.

The Solidity pricing tests read this committed JSON file directly rather than
maintaining a separate set of expected call values. The Python suite also
measures the selected bounded CDF approximation against `math.erf` over 1,601
points from `-8` through `8`.
