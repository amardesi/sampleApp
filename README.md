Steps to get sample app running:

1. Install packages: `./setup.sh`

2. Start proxy connection to database server: `ssh -C -N -L3306:rds-pub-eschol-dev.cmcguhglinoa.us-west-2.rds.amazonaws.com:3306 cdl-aws-bastion.cdlib.org -p 18822`

3. Configure database connection parameters: `cp config/database.yaml.TEMPLATE config/database.yaml`, then fill in the values in `database.yaml`:
  * host: 127.0.0.1
  * port: 3306
  * database: eschol_test
  * username: secret
  * password: secret

4. Run `gulp`. Be on the lookout for errors.

5. Browse to `http://localhost:4001/unit/root`

