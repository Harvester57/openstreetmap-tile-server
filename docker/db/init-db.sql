-- Create the rendering user if it doesn't exist
DO $$
BEGIN
    IF NOT EXISTS (SELECT FROM pg_catalog.pg_roles WHERE rolname = '_renderd') THEN
        CREATE ROLE _renderd WITH LOGIN PASSWORD '_renderd';
    END IF;
END
$$;

-- Grant privileges on the default 'gis' database to the rendering user
GRANT ALL PRIVILEGES ON DATABASE gis TO _renderd;

-- Enable required PostGIS and HStore extensions in the 'gis' database
CREATE EXTENSION IF NOT EXISTS postgis;
CREATE EXTENSION IF NOT EXISTS hstore;

-- Make _renderd the owner of the database
ALTER DATABASE gis OWNER TO _renderd;

-- Set correct owner for spatial reference tables so renderd/osm2pgsql can access them
ALTER TABLE IF EXISTS geometry_columns OWNER TO _renderd;
ALTER TABLE IF EXISTS spatial_ref_sys OWNER TO _renderd;
