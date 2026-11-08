PY ?= .venv/bin/python
.PHONY: setup data facts site serve service
setup:
	python3.13 -m venv .venv
	.venv/bin/pip install -r requirements.txt
# Every source, start to finish. Slow, and it downloads: run it only to refresh the data.
data:
	$(PY) src/notoriety.py fetch
	$(PY) src/notoriety.py build
	$(PY) src/atlas.py fetch
	$(PY) src/atlas.py geo
	$(PY) src/atlas.py climate
	$(PY) src/atlasland.py plant
	$(PY) src/atlasland.py terrain
	$(PY) src/atlasland.py plots
	$(PY) src/atlasland.py rocks
	$(PY) src/atlas.py facts
# Rebuild each place's page data from what is already in regions/.
facts:
	$(PY) src/atlas.py facts
# Write public/, the folder Vercel serves.
site: facts
	$(PY) src/atlas.py site
serve:
	$(PY) src/serve.py
service:
	$(PY) src/service.py install
