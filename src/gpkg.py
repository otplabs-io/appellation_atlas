"""Read a GeoPackage geometry blob, as the EU wine PDO file stores them."""
import struct
from shapely import wkb
def gpkg_geom(b):
    """A GeoPackage geometry blob: 'GP', version, flags, srs id, an envelope sized by the flags, then WKB."""
    flags=b[3]; env={0:0,1:32,2:48,3:48,4:64}[(flags>>1)&7]
    return wkb.loads(bytes(b[8+env:]))
