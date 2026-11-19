# MakeHuman HM08

The four playable students, the opening teacher and the seated classroom extras use the head and hand topology of the MakeHuman HM08 base mesh. MakeHuman released the mesh under CC0 in September 2020. The mesh credits Data Collection AB, Joel Palmius and Jonas Hauquier. The generator pins the original OBJ by commit and SHA-256. [Source](https://github.com/makehumancommunity/makehuman/blob/a8bc2d54ff0ac92e78ff71431b1023eda42bf482/makehuman/data/3dobjs/base.obj) · [License](LICENSE.md)

The otherworld students, teacher, patroller and garage figure also use the HM08 head topology. Their facial shapes, vertex-colour pigments, hair and clothing are authored in `tools/remodel/otherworld.py`.

The playable student designs, face variations, hair, outfits, equipment, skeleton and animation are authored in `tools/remodel/student_cast.py` and `student_motion.py`. Rebuild the playable cast with `python3 tools/remodel/student_cast.py` and the otherworld cast with `python3 tools/remodel/otherworld.py` (NumPy). Both generators accept a local HM08 OBJ with `--base`.
