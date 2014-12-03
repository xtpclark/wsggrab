-- Function: public.getpkgver(text)

DROP FUNCTION public.getpkgver(text);

CREATE OR REPLACE FUNCTION public.getpkgver(text)
  RETURNS text AS
$BODY$
-- Copyright (c) 1999-2014 by OpenMFG LLC, d/b/a xTuple.
-- See www.xtuple.com/CPAL for the full text of the software license.
DECLARE
  pPkgName ALIAS FOR $1;
  _returnVal TEXT;
BEGIN
  IF (pPkgName IS NULL) THEN
        RETURN NULL;
  END IF;

  SELECT pkghead_version INTO _returnVal
  FROM pkghead
  WHERE (pkghead_name=pPkgName);

  IF (_returnVal IS NULL) THEN
        RAISE EXCEPTION 'Package % not found.', pPkgName;
  END IF;

  RETURN _returnVal;
END;
$BODY$
  LANGUAGE plpgsql VOLATILE;
ALTER FUNCTION public.getpkgver(text)
  OWNER TO admin;
