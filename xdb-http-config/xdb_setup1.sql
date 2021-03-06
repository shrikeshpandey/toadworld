/*
||  Name:    xdb_setup1.sql
||  Author:  Michael McLaughlin
||  Date:    29-Feb-2016
|| -------------------------------------------------------------------
||  Description:
||    - Designed to configure standalone XDB Server for PL/SQL
||      programs that run from an unsecured HTTP URL.
||
||    - This checks for the default port and resets it when necessary,
||      necessary creates a STUDENT_DAD Data Access Descriptor (DAD),
||      and authorizes the STUDENT_DAD to run programs.
|| -------------------------------------------------------------------
||  Instructions:
||    You should run this as the SYSTEM user inside 
|| -------------------------------------------------------------------
||  Revisions:
||    
||
*/

/* Block checks and resets default port. */
DECLARE
  lv_port  NUMBER;
BEGIN
  SELECT dbms_xdb.gethttpport()
  INTO   lv_port
  FROM dual;

  /* Check for default port and reset. */
  IF NOT lv_port = 8080 THEN
    dbms_xdb.sethttpport(8080);
  END IF;
END;
/

/* Block creates a data access descriptor (DAD) when one does not exist. */
DECLARE
  /* Declare variables. */
  lv_path_name  VARCHAR2(80) := '/studentdb/*';
  lv_dad_name   VARCHAR2(80) := 'STUDENT_DAD';
  lv_return     VARCHAR2(1);

  /* Declare DAD discovery. */
  CURSOR c
  ( cv_path_name  VARCHAR2
  , cv_dad_name   VARCHAR2 ) IS
    SELECT   null
    FROM     xdb.xdb$config cfg CROSS JOIN
             TABLE(XMLSequence( extract(cfg.object_value
             ,                 '/xdbconfig/sysconfig/protocolconfig/httpconfig'
             ||                '/webappconfig/servletconfig/servlet-mappings'
             ||                '/servlet-mapping'))) map CROSS JOIN
             TABLE(XMLSequence( extract(cfg.object_value
             ,                 '/xdbconfig/sysconfig/protocolconfig/httpconfig'
             ||                '/webappconfig/servletconfig/servlet-list'
             ||                '/servlet[servlet-language="PL/SQL"]'
             ,                 'xmlns="http://xmlns.oracle.com/xdb/xdbconfig.xsd"'))) dad
    WHERE    extractValue( value(map)
             ,            '/servlet-mapping/servlet-name'
             ,            'xmlns="http://xmlns.oracle.com/xdb/xdbconfig.xsd"') =
               extractValue( value(dad)
               ,            '/servlet/servlet-name'
               ,            'xmlns="http://xmlns.oracle.com/xdb/xdbconfig.xsd"')
    AND      extractValue( value(map)
             ,            '/servlet-mapping/servlet-pattern'
             ,            'xmlns="http://xmlns.oracle.com/xdb/xdbconfig.xsd"') = cv_path_name
    AND      extractValue( value(map)
             ,            '/servlet-mapping/servlet-name'
             ,            'xmlns="http://xmlns.oracle.com/xdb/xdbconfig.xsd"') = cv_dad_name;

BEGIN
  OPEN c(lv_path_name, lv_dad_name);
  FETCH c INTO lv_return;
  IF c%NOTFOUND THEN
      dbms_output.put_line('Created '||lv_dad_name||' DAD.');
    dbms_epg.create_dad(
      dad_name => lv_dad_name
    , path =>     lv_path_name);
  ELSE
    dbms_output.put_line(lv_dad_name||' DAD already exists.');
  END IF;
  CLOSE c;
END;
/

/* Block authorizes a data access descriptor (DAD). */
DECLARE
  /* Create record type for authorization cursor. */
  TYPE dad_authorization IS RECORD
  ( dad_name     VARCHAR2(80)
  , username     VARCHAR2(80)
  , auth_schema  VARCHAR2(80));

  /* Declare variables. */
  lv_dad_name   VARCHAR2(80) := 'STUDENT_DAD';
  lv_authority  DAD_AUTHORIZATION;

  /* Declare DAD discovery. */
  CURSOR c
  ( cv_dad_name   VARCHAR2 ) IS
    SELECT   deda.username
    FROM     dba_epg_dad_authorization deda
    WHERE    deda.dad_name = lv_dad_name;

  /* Verify a DAD authorization. */
  CURSOR v
  ( cv_dad_name  VARCHAR2 ) IS
    SELECT   cfg.dad_name
    ,        cfg.username
    ,        CASE
               WHEN cfg.username = 'ANONYMOUS' THEN 'Anonymous'
               WHEN auth.username IS NULL THEN
                 CASE
                   WHEN cfg.username IS NULL THEN 'Dynamic'
                   ELSE 'Dynamic Restricted'
                 END
               ELSE 'Static'
             END auth_schema
    FROM    (SELECT   extractValue( value(dad)
                      ,            '/servlet/servlet-name'
                      ,            'xmlns="http://xmlns.oracle.com/xdb/xdbconfig.xsd"') dad_name
             ,        extractValue( value(dad)
                      ,            '/servlet/plsql/database-username'
                      ,            'xmlns="http://xmlns.oracle.com/xdb/xdbconfig.xsd"') username
             FROM     xdb.xdb$config cfg CROSS JOIN
                      TABLE(XMLSequence(extract( cfg.object_value
                                       ,        '/xdbconfig/sysconfig/protocolconfig/httpconfig'
                                       ||       '/webappconfig/servletconfig/servlet-list'
                                       ||       '/servlet[servlet-language="PL/SQL"]'
                                       ,        'xmlns="http://xmlns.oracle.com/xdb/xdbconfig.xsd"'))) dad) cfg,
                      dba_epg_dad_authorization auth
    WHERE    cfg.dad_name = auth.dad_name(+)
    AND      cfg.username = auth.username(+)
    AND      cfg.dad_name = cv_dad_name;
BEGIN
  FOR i IN c(lv_dad_name) LOOP
    OPEN v(lv_dad_name);
    FETCH v INTO lv_authority;
    IF v%NOTFOUND THEN
      dbms_output.put_line('Authorize '||lv_dad_name||' DAD.');
      dbms_epg.authorize_dad(
        dad_name => lv_dad_name
      , user => i.username);
    ELSE
      dbms_output.put_line(lv_dad_name||' DAD already authorized.');
    END IF;
    CLOSE v;
  END LOOP;
END;
/
