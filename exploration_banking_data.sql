--==============================================================================
-- Script d'exploration : cartographie Clients / Comptes / KYC
-- Cible : Oracle 12c (FLEXCUBE)
-- Mode  : SELECT only
-- Usage : SQL*Plus / SQLcl  ->  @exploration_banking_data.sql
-- Sortie: rapport texte via DBMS_OUTPUT
--==============================================================================
SET SERVEROUTPUT ON SIZE UNLIMITED FORMAT WRAPPED
SET LINESIZE 300
SET PAGESIZE 0
SET FEEDBACK OFF
SET VERIFY  OFF
SET TIMING  OFF
SET TRIMSPOOL ON

DECLARE
    -- ------------------------------------------------------------------------
    -- Helpers d'affichage
    -- ------------------------------------------------------------------------
    PROCEDURE p(s IN VARCHAR2 DEFAULT NULL) IS
    BEGIN
        DBMS_OUTPUT.PUT_LINE(NVL(s,' '));
    END;

    PROCEDURE hdr(title IN VARCHAR2) IS
    BEGIN
        p('');
        p(RPAD('=',100,'='));
        p(title);
        p(RPAD('=',100,'='));
    END;

    PROCEDURE sub(title IN VARCHAR2) IS
    BEGIN
        p('');
        p('--- ' || title || ' ' || RPAD('-', GREATEST(95-LENGTH(title),3),'-'));
    END;

    -- comptage rapide d'une table (nom dynamique, securise par REGEXP)
    FUNCTION cnt(p_table IN VARCHAR2) RETURN NUMBER IS
        v_n NUMBER;
    BEGIN
        IF NOT REGEXP_LIKE(p_table,'^[A-Z0-9_$#]+$') THEN
            RETURN -1;
        END IF;
        EXECUTE IMMEDIATE 'SELECT COUNT(*) FROM '||p_table INTO v_n;
        RETURN v_n;
    EXCEPTION WHEN OTHERS THEN RETURN -1;
    END;

    v_n NUMBER;
BEGIN
    p('RAPPORT EXPLORATION BANKING DATA - genere le ' ||
      TO_CHAR(SYSDATE,'YYYY-MM-DD HH24:MI:SS'));

    --==========================================================================
    -- SECTION 1 - INVENTAIRE DES TABLES PERTINENTES
    --==========================================================================
    hdr('SECTION 1 - INVENTAIRE DES TABLES PERTINENTES');

    sub('1.1 Tables candidates (USER_TABLES) - mots-cles CUST/CIF/ACCOUNT/ACCT/KYC/DOC');
    p(RPAD('TABLE_NAME',40)||RPAD('NUM_ROWS',15)||RPAD('LAST_ANALYZED',22)||'COMMENT');
    p(RPAD('-',100,'-'));
    FOR r IN (
        SELECT  t.table_name,
                t.num_rows,
                t.last_analyzed,
                tc.comments
        FROM    user_tables t
        LEFT JOIN user_tab_comments tc ON tc.table_name = t.table_name
        WHERE   REGEXP_LIKE(t.table_name,'CUST|CIF|ACCOUNT|ACCT|KYC|DOC','i')
        ORDER BY t.num_rows DESC NULLS LAST
    ) LOOP
        p(RPAD(r.table_name,40)||
          RPAD(NVL(TO_CHAR(r.num_rows),'(no stats)'),15)||
          RPAD(NVL(TO_CHAR(r.last_analyzed,'YYYY-MM-DD HH24:MI'),'-'),22)||
          NVL(SUBSTR(r.comments,1,60),''));
    END LOOP;

    sub('1.2 Vues candidates (USER_VIEWS)');
    p(RPAD('VIEW_NAME',45)||'COMMENT');
    p(RPAD('-',100,'-'));
    FOR r IN (
        SELECT  v.view_name, vc.comments
        FROM    user_views v
        LEFT JOIN user_tab_comments vc ON vc.table_name = v.view_name
        WHERE   REGEXP_LIKE(v.view_name,'CUST|CIF|ACCOUNT|ACCT|KYC|DOC','i')
        ORDER BY v.view_name
    ) LOOP
        p(RPAD(r.view_name,45)||NVL(SUBSTR(r.comments,1,60),''));
    END LOOP;

    sub('1.3 Synonymes pointant vers les tables/vues candidates');
    p(RPAD('SYNONYM',35)||RPAD('OWNER',15)||'TABLE_NAME');
    p(RPAD('-',100,'-'));
    FOR r IN (
        SELECT synonym_name, table_owner, table_name
        FROM   user_synonyms
        WHERE  REGEXP_LIKE(table_name,'CUST|CIF|ACCOUNT|ACCT|KYC|DOC','i')
        ORDER BY synonym_name
    ) LOOP
        p(RPAD(r.synonym_name,35)||RPAD(NVL(r.table_owner,'-'),15)||r.table_name);
    END LOOP;

    sub('1.4 Comptage REEL des tables cibles (independant des stats)');
    p(RPAD('TABLE',40)||'COUNT(*)');
    p(RPAD('-',60,'-'));
    FOR r IN (
        SELECT column_value AS tbl FROM TABLE(sys.odcivarchar2list(
            'STTM_CUSTOMER','STTM_CUST_PERSONAL','STTM_CUST_ACCOUNT',
            'STTB_ACCOUNT','STTM_ACCOUNT_CLASS','STTM_CUSTOMER_CAT',
            'STTM_KYC_MASTER','STTM_KYC_RETAIL','STTM_KYC_CORPORATE',
            'STTM_KYC_CORP_KEYPERSONS',
            'CLTB_ACCOUNT_APPS_MASTER','CLTB_ACCOUNT_COMPONENTS','CLTB_ACCOUNT_SCHEDULES'))
    ) LOOP
        v_n := cnt(r.tbl);
        p(RPAD(r.tbl,40)||
          CASE WHEN v_n=-1 THEN '(table absente / erreur)' ELSE TO_CHAR(v_n) END);
    END LOOP;

END;
/

DECLARE
    PROCEDURE p(s IN VARCHAR2 DEFAULT NULL) IS
    BEGIN DBMS_OUTPUT.PUT_LINE(NVL(s,' ')); END;
    PROCEDURE hdr(t IN VARCHAR2) IS
    BEGIN p(''); p(RPAD('=',100,'=')); p(t); p(RPAD('=',100,'=')); END;
    PROCEDURE sub(t IN VARCHAR2) IS
    BEGIN p(''); p('--- '||t||' '||RPAD('-',GREATEST(95-LENGTH(t),3),'-')); END;

    -- liste des tables cibles - reutilisee dans toutes les sections suivantes
    TYPE t_tbls IS TABLE OF VARCHAR2(30);
    g_tbls CONSTANT t_tbls := t_tbls(
        'STTM_CUSTOMER','STTM_CUST_PERSONAL','STTM_CUST_ACCOUNT',
        'STTB_ACCOUNT','STTM_ACCOUNT_CLASS','STTM_CUSTOMER_CAT',
        'STTM_KYC_MASTER','STTM_KYC_RETAIL','STTM_KYC_CORPORATE',
        'STTM_KYC_CORP_KEYPERSONS');
    v_n NUMBER;
BEGIN
    --==========================================================================
    -- SECTION 2 - EXPLORATION DE STRUCTURE
    --==========================================================================
    hdr('SECTION 2 - EXPLORATION DE STRUCTURE');

    sub('2.1 Resume structurel par table (nb colonnes / index / PK)');
    p(RPAD('TABLE',32)||RPAD('NUM_ROWS',12)||RPAD('NB_COLS',10)||
      RPAD('NB_IDX',10)||'HAS_PK');
    p(RPAD('-',80,'-'));
    FOR r IN (
        SELECT  t.table_name,
                t.num_rows,
                (SELECT COUNT(*) FROM user_tab_columns c WHERE c.table_name=t.table_name) nb_cols,
                (SELECT COUNT(*) FROM user_indexes     i WHERE i.table_name=t.table_name) nb_idx,
                (SELECT COUNT(*) FROM user_constraints u
                  WHERE  u.table_name=t.table_name AND u.constraint_type='P')             has_pk
        FROM    user_tables t
        WHERE   t.table_name MEMBER OF g_tbls
        ORDER BY t.num_rows DESC NULLS LAST
    ) LOOP
        p(RPAD(r.table_name,32)||
          RPAD(NVL(TO_CHAR(r.num_rows),'-'),12)||
          RPAD(TO_CHAR(r.nb_cols),10)||
          RPAD(TO_CHAR(r.nb_idx),10)||
          CASE WHEN r.has_pk>0 THEN 'YES' ELSE 'NO' END);
    END LOOP;

    sub('2.2 Cles primaires / uniques');
    p(RPAD('TABLE',32)||RPAD('TYPE',6)||RPAD('CONSTRAINT',32)||'COLUMNS');
    p(RPAD('-',100,'-'));
    FOR r IN (
        SELECT  uc.table_name,
                uc.constraint_type,
                uc.constraint_name,
                LISTAGG(ucc.column_name,',')
                    WITHIN GROUP (ORDER BY ucc.position) AS cols
        FROM    user_constraints  uc
        JOIN    user_cons_columns ucc ON ucc.constraint_name=uc.constraint_name
        WHERE   uc.table_name MEMBER OF g_tbls
           AND  uc.constraint_type IN ('P','U')
        GROUP BY uc.table_name, uc.constraint_type, uc.constraint_name
        ORDER BY uc.table_name, uc.constraint_type
    ) LOOP
        p(RPAD(r.table_name,32)||RPAD(r.constraint_type,6)||
          RPAD(SUBSTR(r.constraint_name,1,30),32)||r.cols);
    END LOOP;

    sub('2.3 Cles etrangeres declarees');
    p(RPAD('CHILD_TABLE',32)||RPAD('CHILD_COLS',30)||RPAD('PARENT_TABLE',30)||'PARENT_COLS');
    p(RPAD('-',120,'-'));
    FOR r IN (
        SELECT  uc.table_name      AS child_table,
                LISTAGG(ucc.column_name,',') WITHIN GROUP (ORDER BY ucc.position) AS child_cols,
                rc.table_name      AS parent_table,
                LISTAGG(rcc.column_name,',') WITHIN GROUP (ORDER BY rcc.position) AS parent_cols
        FROM    user_constraints  uc
        JOIN    user_cons_columns ucc ON ucc.constraint_name = uc.constraint_name
        JOIN    user_constraints  rc  ON rc.constraint_name  = uc.r_constraint_name
        JOIN    user_cons_columns rcc ON rcc.constraint_name = rc.constraint_name
                                      AND rcc.position       = ucc.position
        WHERE   uc.constraint_type = 'R'
           AND  uc.table_name MEMBER OF g_tbls
        GROUP BY uc.table_name, rc.table_name
        ORDER BY uc.table_name
    ) LOOP
        p(RPAD(r.child_table,32)||RPAD(SUBSTR(r.child_cols,1,28),30)||
          RPAD(r.parent_table,30)||r.parent_cols);
    END LOOP;
    SELECT COUNT(*) INTO v_n
    FROM   user_constraints uc
    WHERE  uc.constraint_type='R' AND uc.table_name MEMBER OF g_tbls;
    IF v_n = 0 THEN
        p('(aucune FK declaree sur les tables cibles - typique FLEXCUBE)');
    END IF;

    sub('2.4 Index disponibles');
    p(RPAD('TABLE',30)||RPAD('INDEX_NAME',32)||RPAD('UNIQ',6)||'COLUMNS');
    p(RPAD('-',120,'-'));
    FOR r IN (
        SELECT  i.table_name, i.index_name, i.uniqueness,
                LISTAGG(ic.column_name,',') WITHIN GROUP (ORDER BY ic.column_position) cols
        FROM    user_indexes i
        JOIN    user_ind_columns ic ON ic.index_name=i.index_name
        WHERE   i.table_name MEMBER OF g_tbls
        GROUP BY i.table_name, i.index_name, i.uniqueness
        ORDER BY i.table_name, i.uniqueness DESC
    ) LOOP
        p(RPAD(r.table_name,30)||RPAD(SUBSTR(r.index_name,1,30),32)||
          RPAD(SUBSTR(r.uniqueness,1,4),6)||r.cols);
    END LOOP;

    sub('2.5 Detail colonnes des tables cles (type, longueur, nullable)');
    p(RPAD('TABLE',28)||RPAD('COL',32)||RPAD('TYPE',12)||
      RPAD('LEN',6)||RPAD('NULL',6)||'DEFAULT');
    p(RPAD('-',110,'-'));
    FOR r IN (
        SELECT  c.table_name, c.column_id, c.column_name, c.data_type,
                c.data_length, c.nullable, c.data_default
        FROM    user_tab_columns c
        WHERE   c.table_name MEMBER OF g_tbls
        ORDER BY c.table_name, c.column_id
    ) LOOP
        p(RPAD(r.table_name,28)||RPAD(SUBSTR(r.column_name,1,30),32)||
          RPAD(r.data_type,12)||RPAD(NVL(TO_CHAR(r.data_length),'-'),6)||
          RPAD(r.nullable,6)||NVL(SUBSTR(r.data_default,1,30),''));
    END LOOP;

    sub('2.6 Commentaires de colonnes (semantique metier - si renseignes)');
    FOR r IN (
        SELECT cc.table_name, cc.column_name, cc.comments
        FROM   user_col_comments cc
        WHERE  cc.table_name MEMBER OF g_tbls
          AND  cc.comments IS NOT NULL
        ORDER BY cc.table_name, cc.column_name
    ) LOOP
        p(RPAD(r.table_name,28)||RPAD(r.column_name,32)||SUBSTR(r.comments,1,60));
    END LOOP;
END;
/

DECLARE
    PROCEDURE p(s IN VARCHAR2 DEFAULT NULL) IS
    BEGIN DBMS_OUTPUT.PUT_LINE(NVL(s,' ')); END;
    PROCEDURE hdr(t IN VARCHAR2) IS
    BEGIN p(''); p(RPAD('=',100,'=')); p(t); p(RPAD('=',100,'=')); END;
    PROCEDURE sub(t IN VARCHAR2) IS
    BEGIN p(''); p('--- '||t||' '||RPAD('-',GREATEST(95-LENGTH(t),3),'-')); END;

    -- profile une colonne d'une table : nb_rows, distinct, nulls
    PROCEDURE profile_col(p_tbl IN VARCHAR2, p_col IN VARCHAR2) IS
        v_tot   NUMBER; v_nn  NUMBER; v_dist NUMBER;
    BEGIN
        EXECUTE IMMEDIATE
            'SELECT COUNT(*), COUNT("'||p_col||'"), COUNT(DISTINCT "'||p_col||'") FROM '||p_tbl
            INTO v_tot, v_nn, v_dist;
        p(RPAD(p_tbl,28)||RPAD(p_col,28)||
          RPAD(TO_CHAR(v_tot),12)||RPAD(TO_CHAR(v_dist),12)||
          RPAD(TO_CHAR(v_tot-v_nn),12)||
          LPAD(TO_CHAR(ROUND((v_tot-v_nn)*100/NULLIF(v_tot,0),2),'990.00')||'%',8));
    EXCEPTION WHEN OTHERS THEN
        p(RPAD(p_tbl,28)||RPAD(p_col,28)||'(erreur: '||SQLERRM||')');
    END;
BEGIN
    --==========================================================================
    -- SECTION 3 - PROFILING DES DONNEES
    --==========================================================================
    hdr('SECTION 3 - PROFILING DES DONNEES');

    sub('3.1 Profilage des colonnes critiques (TOTAL / DISTINCT / NULL / %NULL)');
    p(RPAD('TABLE',28)||RPAD('COLUMN',28)||RPAD('TOTAL',12)||
      RPAD('DISTINCT',12)||RPAD('NULL',12)||'%NULL');
    p(RPAD('-',100,'-'));

    -- STTM_CUSTOMER
    profile_col('STTM_CUSTOMER',     'CUSTOMER_NO');
    profile_col('STTM_CUSTOMER',     'UNIQUE_ID_VALUE');
    profile_col('STTM_CUSTOMER',     'KYC_REF_NO');
    profile_col('STTM_CUSTOMER',     'CUSTOMER_NAME1');
    profile_col('STTM_CUSTOMER',     'SHORT_NAME');
    profile_col('STTM_CUSTOMER',     'NATIONALITY');
    profile_col('STTM_CUSTOMER',     'CUSTOMER_TYPE');
    profile_col('STTM_CUSTOMER',     'CUSTOMER_CATEGORY');
    profile_col('STTM_CUSTOMER',     'CIF_STATUS');
    profile_col('STTM_CUSTOMER',     'LIABILITY_NO');
    -- STTM_CUST_PERSONAL
    profile_col('STTM_CUST_PERSONAL','CUSTOMER_NO');
    profile_col('STTM_CUST_PERSONAL','P_NATIONAL_ID');
    profile_col('STTM_CUST_PERSONAL','PASSPORT_NO');
    profile_col('STTM_CUST_PERSONAL','FIRST_NAME');
    profile_col('STTM_CUST_PERSONAL','LAST_NAME');
    profile_col('STTM_CUST_PERSONAL','DATE_OF_BIRTH');
    profile_col('STTM_CUST_PERSONAL','SEX');
    profile_col('STTM_CUST_PERSONAL','E_MAIL');
    profile_col('STTM_CUST_PERSONAL','MOBILE_NUMBER');
    -- STTM_CUST_ACCOUNT
    profile_col('STTM_CUST_ACCOUNT', 'CUST_AC_NO');
    profile_col('STTM_CUST_ACCOUNT', 'CUST_NO');
    profile_col('STTM_CUST_ACCOUNT', 'IBAN_AC_NO');
    profile_col('STTM_CUST_ACCOUNT', 'AC_DESC');
    profile_col('STTM_CUST_ACCOUNT', 'CCY');
    profile_col('STTM_CUST_ACCOUNT', 'BRANCH_CODE');
    profile_col('STTM_CUST_ACCOUNT', 'ACCOUNT_CLASS');
    profile_col('STTM_CUST_ACCOUNT', 'ACCOUNT_TYPE');
    profile_col('STTM_CUST_ACCOUNT', 'ACC_STATUS');
    profile_col('STTM_CUST_ACCOUNT', 'AC_OPEN_DATE');
    -- STTB_ACCOUNT
    profile_col('STTB_ACCOUNT',      'AC_GL_NO');
    profile_col('STTB_ACCOUNT',      'CUST_NO');
    profile_col('STTB_ACCOUNT',      'AC_OR_GL');
    profile_col('STTB_ACCOUNT',      'AC_CLASS');
    profile_col('STTB_ACCOUNT',      'BRANCH_CODE');
    -- KYC
    profile_col('STTM_KYC_MASTER',   'KYC_REF_NO');
    profile_col('STTM_KYC_MASTER',   'KYC_CUST_TYPE');
    profile_col('STTM_KYC_MASTER',   'RISK_LEVEL');
    profile_col('STTM_KYC_RETAIL',   'KYC_REF_NO');
    profile_col('STTM_KYC_RETAIL',   'BIRTH_DATE');
    profile_col('STTM_KYC_RETAIL',   'NATIONALITY');
    profile_col('STTM_KYC_RETAIL',   'PASSPORT_NO');
    profile_col('STTM_KYC_RETAIL',   'TOTAL_INCOME');
    profile_col('STTM_KYC_CORPORATE','KYC_REF_NO');
    profile_col('STTM_KYC_CORPORATE','COMPANY_TYPE');
    profile_col('STTM_KYC_CORPORATE','TRADE_LICENCE_NO');
    profile_col('STTM_KYC_CORPORATE','ANNUAL_TURNOVER');

    sub('3.2 Champs vides (TRIM=empty) sur identifiants critiques');
    DECLARE v NUMBER;
    BEGIN
        SELECT COUNT(*) INTO v FROM STTM_CUSTOMER
         WHERE customer_name1 IS NULL OR TRIM(customer_name1) IS NULL;
        p('STTM_CUSTOMER.CUSTOMER_NAME1 vide      : '||v);
        SELECT COUNT(*) INTO v FROM STTM_CUSTOMER
         WHERE short_name IS NULL OR TRIM(short_name) IS NULL;
        p('STTM_CUSTOMER.SHORT_NAME vide          : '||v);
        SELECT COUNT(*) INTO v FROM STTM_CUST_PERSONAL
         WHERE first_name IS NULL OR TRIM(first_name) IS NULL;
        p('STTM_CUST_PERSONAL.FIRST_NAME vide     : '||v);
        SELECT COUNT(*) INTO v FROM STTM_CUST_PERSONAL
         WHERE last_name IS NULL OR TRIM(last_name) IS NULL;
        p('STTM_CUST_PERSONAL.LAST_NAME vide      : '||v);
        SELECT COUNT(*) INTO v FROM STTM_CUST_ACCOUNT
         WHERE ac_desc IS NULL OR TRIM(ac_desc) IS NULL;
        p('STTM_CUST_ACCOUNT.AC_DESC vide         : '||v);
    END;
END;
/

DECLARE
    PROCEDURE p(s IN VARCHAR2 DEFAULT NULL) IS
    BEGIN DBMS_OUTPUT.PUT_LINE(NVL(s,' ')); END;
    PROCEDURE hdr(t IN VARCHAR2) IS
    BEGIN p(''); p(RPAD('=',100,'=')); p(t); p(RPAD('=',100,'=')); END;
    PROCEDURE sub(t IN VARCHAR2) IS
    BEGIN p(''); p('--- '||t||' '||RPAD('-',GREATEST(95-LENGTH(t),3),'-')); END;

    -- distribution des valeurs distinctes d'une colonne d'enumeration
    PROCEDURE distrib(p_tbl  IN VARCHAR2,
                      p_col  IN VARCHAR2,
                      p_top  IN NUMBER DEFAULT 30) IS
        v_sql VARCHAR2(4000);
        TYPE t_rec IS RECORD (val VARCHAR2(200), nb NUMBER);
        TYPE t_tab IS TABLE OF t_rec;
        l_tab t_tab;
        v_total NUMBER;
    BEGIN
        EXECUTE IMMEDIATE 'SELECT COUNT(*) FROM '||p_tbl INTO v_total;
        v_sql :=
            'SELECT * FROM ('||
            '  SELECT NVL(TO_CHAR("'||p_col||'"),''(NULL)'') AS val, COUNT(*) AS nb '||
            '  FROM '||p_tbl||' GROUP BY "'||p_col||'" ORDER BY 2 DESC) '||
            'WHERE ROWNUM <= :tp';
        EXECUTE IMMEDIATE v_sql BULK COLLECT INTO l_tab USING p_top;

        p('');
        p('>> '||p_tbl||'.'||p_col||'  (total='||v_total||', top '||p_top||')');
        p(RPAD('VALUE',45)||RPAD('COUNT',12)||'PCT');
        p(RPAD('-',75,'-'));
        FOR i IN 1..l_tab.COUNT LOOP
            p(RPAD(SUBSTR(l_tab(i).val,1,43),45)||
              RPAD(TO_CHAR(l_tab(i).nb),12)||
              TO_CHAR(ROUND(l_tab(i).nb*100/NULLIF(v_total,0),2),'990.00')||'%');
        END LOOP;
    EXCEPTION WHEN OTHERS THEN
        p('>> '||p_tbl||'.'||p_col||' : erreur '||SQLERRM);
    END;
BEGIN
    --==========================================================================
    -- SECTION 4 - ANALYSE DES CODIFICATIONS
    --==========================================================================
    hdr('SECTION 4 - ANALYSE DES CODIFICATIONS');

    sub('4.1 STTM_CUSTOMER : statuts, types, categories');
    distrib('STTM_CUSTOMER','CUSTOMER_TYPE');         -- I=Individual, C=Corporate, B=Bank
    distrib('STTM_CUSTOMER','CUSTOMER_CATEGORY');
    distrib('STTM_CUSTOMER','CUST_CLASSIFICATION');
    distrib('STTM_CUSTOMER','CIF_STATUS');
    distrib('STTM_CUSTOMER','RISK_CATEGORY');
    distrib('STTM_CUSTOMER','RECORD_STAT');           -- O=Open, C=Closed
    distrib('STTM_CUSTOMER','AUTH_STAT');             -- A=Authorized, U=Unauthorized
    distrib('STTM_CUSTOMER','FROZEN');
    distrib('STTM_CUSTOMER','DECEASED');
    distrib('STTM_CUSTOMER','WHEREABOUTS_UNKNOWN');
    distrib('STTM_CUSTOMER','NATIONALITY', 50);
    distrib('STTM_CUSTOMER','LANGUAGE');
    distrib('STTM_CUSTOMER','UNIQUE_ID_NAME');        -- type d'ID utilise

    sub('4.2 STTM_CUST_PERSONAL : sex, resident_status');
    distrib('STTM_CUST_PERSONAL','SEX');
    distrib('STTM_CUST_PERSONAL','RESIDENT_STATUS');
    distrib('STTM_CUST_PERSONAL','MINOR');
    distrib('STTM_CUST_PERSONAL','US_RES_STATUS');

    sub('4.3 STTM_CUST_ACCOUNT : statuts, types, classes');
    distrib('STTM_CUST_ACCOUNT','ACCOUNT_TYPE');      -- S=Savings, U=Current,...
    distrib('STTM_CUST_ACCOUNT','ACC_STATUS');        -- NORM, DORM, CLOS,...
    distrib('STTM_CUST_ACCOUNT','ACCOUNT_CLASS', 50);
    distrib('STTM_CUST_ACCOUNT','CCY');
    distrib('STTM_CUST_ACCOUNT','BRANCH_CODE', 50);
    distrib('STTM_CUST_ACCOUNT','RECORD_STAT');
    distrib('STTM_CUST_ACCOUNT','AUTH_STAT');
    distrib('STTM_CUST_ACCOUNT','AC_STAT_DORMANT');
    distrib('STTM_CUST_ACCOUNT','AC_STAT_FROZEN');
    distrib('STTM_CUST_ACCOUNT','AC_STAT_NO_DR');
    distrib('STTM_CUST_ACCOUNT','AC_STAT_NO_CR');
    distrib('STTM_CUST_ACCOUNT','AC_STAT_BLOCK');
    distrib('STTM_CUST_ACCOUNT','AC_STAT_STOP_PAY');

    sub('4.4 STTB_ACCOUNT : nature comptable');
    distrib('STTB_ACCOUNT','AC_OR_GL');               -- A=Account, G=GL
    distrib('STTB_ACCOUNT','GL_CATEGORY');
    distrib('STTB_ACCOUNT','AC_CLASS', 50);
    distrib('STTB_ACCOUNT','AC_STAT_DORMANT');
    distrib('STTB_ACCOUNT','AC_STAT_FROZEN');
    distrib('STTB_ACCOUNT','GL_STAT_BLOCKED');
    distrib('STTB_ACCOUNT','AUTH_STAT');

    sub('4.5 KYC : risk level, types');
    distrib('STTM_KYC_MASTER','KYC_CUST_TYPE');
    distrib('STTM_KYC_MASTER','RISK_LEVEL');
    distrib('STTM_KYC_MASTER','RECORD_STAT');
    distrib('STTM_KYC_MASTER','AUTH_STAT');
    distrib('STTM_KYC_RETAIL','ACC_TYPE');
    distrib('STTM_KYC_RETAIL','PEP');
    distrib('STTM_KYC_RETAIL','RESIDENT');
    distrib('STTM_KYC_CORPORATE','COMPANY_TYPE');

    sub('4.6 Reference : libelles des categories clients (STTM_CUSTOMER_CAT)');
    p(RPAD('CUST_CAT',15)||'CUST_CAT_DESC');
    p(RPAD('-',80,'-'));
    FOR r IN (SELECT cust_cat, cust_cat_desc FROM STTM_CUSTOMER_CAT ORDER BY cust_cat) LOOP
        p(RPAD(NVL(r.cust_cat,'-'),15)||NVL(r.cust_cat_desc,'-'));
    END LOOP;

    sub('4.7 Reference : classes de comptes (STTM_ACCOUNT_CLASS)');
    p(RPAD('ACCOUNT_CLASS',20)||RPAD('TYPE',8)||'DESC');
    p(RPAD('-',100,'-'));
    FOR r IN (
        SELECT account_class, ac_class_type, description
        FROM   STTM_ACCOUNT_CLASS
        ORDER BY account_class
    ) LOOP
        p(RPAD(r.account_class,20)||RPAD(NVL(r.ac_class_type,'-'),8)||
          NVL(SUBSTR(r.description,1,60),'-'));
    END LOOP;
END;
/

DECLARE
    PROCEDURE p(s IN VARCHAR2 DEFAULT NULL) IS
    BEGIN DBMS_OUTPUT.PUT_LINE(NVL(s,' ')); END;
    PROCEDURE hdr(t IN VARCHAR2) IS
    BEGIN p(''); p(RPAD('=',100,'=')); p(t); p(RPAD('=',100,'=')); END;
    PROCEDURE sub(t IN VARCHAR2) IS
    BEGIN p(''); p('--- '||t||' '||RPAD('-',GREATEST(95-LENGTH(t),3),'-')); END;

    v_n  NUMBER;
    v_n2 NUMBER;
BEGIN
    --==========================================================================
    -- SECTION 5 - RELATIONS ENTRE ENTITES
    --==========================================================================
    hdr('SECTION 5 - RELATIONS ENTRE ENTITES (CIF / COMPTES / KYC)');

    sub('5.1 Cardinalite client <-> compte (STTM_CUSTOMER vs STTM_CUST_ACCOUNT)');
    SELECT COUNT(*)            INTO v_n  FROM STTM_CUSTOMER;
    SELECT COUNT(DISTINCT cust_no) INTO v_n2 FROM STTM_CUST_ACCOUNT;
    p('Clients (STTM_CUSTOMER)              : '||v_n);
    p('Clients distincts dans CUST_ACCOUNT  : '||v_n2);

    sub('5.2 Distribution du nombre de comptes par client');
    p(RPAD('NB_COMPTES',15)||RPAD('NB_CLIENTS',15)||'PCT');
    p(RPAD('-',60,'-'));
    DECLARE v_total NUMBER;
    BEGIN
        SELECT COUNT(*) INTO v_total FROM (
            SELECT cust_no FROM STTM_CUST_ACCOUNT GROUP BY cust_no
        );
        FOR r IN (
            SELECT bucket, COUNT(*) AS nb_clients
            FROM (
                SELECT CASE
                          WHEN nb=1 THEN '1'
                          WHEN nb=2 THEN '2'
                          WHEN nb BETWEEN 3 AND 5 THEN '3-5'
                          WHEN nb BETWEEN 6 AND 10 THEN '6-10'
                          WHEN nb BETWEEN 11 AND 20 THEN '11-20'
                          ELSE '>20'
                       END AS bucket
                FROM (SELECT cust_no, COUNT(*) AS nb
                      FROM STTM_CUST_ACCOUNT GROUP BY cust_no)
            )
            GROUP BY bucket
            ORDER BY DECODE(bucket,'1',1,'2',2,'3-5',3,'6-10',4,'11-20',5,6)
        ) LOOP
            p(RPAD(r.bucket,15)||RPAD(TO_CHAR(r.nb_clients),15)||
              TO_CHAR(ROUND(r.nb_clients*100/NULLIF(v_total,0),2),'990.00')||'%');
        END LOOP;
    END;

    sub('5.3 Top 20 clients avec le plus de comptes');
    p(RPAD('CUSTOMER_NO',20)||RPAD('NB_COMPTES',12)||'CUSTOMER_NAME1');
    p(RPAD('-',100,'-'));
    FOR r IN (
        SELECT * FROM (
            SELECT  a.cust_no,
                    COUNT(*) AS nb,
                    MAX(c.customer_name1) AS nom
            FROM    STTM_CUST_ACCOUNT a
            LEFT JOIN STTM_CUSTOMER  c ON c.customer_no = a.cust_no
            GROUP BY a.cust_no
            ORDER BY 2 DESC
        ) WHERE ROWNUM <= 20
    ) LOOP
        p(RPAD(NVL(r.cust_no,'(NULL)'),20)||RPAD(TO_CHAR(r.nb),12)||
          NVL(SUBSTR(r.nom,1,60),'-'));
    END LOOP;

    sub('5.4 Clients SANS compte (presents dans STTM_CUSTOMER mais absents de STTM_CUST_ACCOUNT)');
    SELECT COUNT(*) INTO v_n FROM (
        SELECT customer_no FROM STTM_CUSTOMER
        MINUS
        SELECT cust_no FROM STTM_CUST_ACCOUNT WHERE cust_no IS NOT NULL
    );
    p('Nombre de clients sans aucun compte : '||v_n);
    p('');
    p('Echantillon (10 premiers) :');
    p(RPAD('CUSTOMER_NO',20)||RPAD('TYPE',6)||RPAD('STATUS',12)||'NAME');
    p(RPAD('-',100,'-'));
    FOR r IN (
        SELECT * FROM (
            SELECT c.customer_no, c.customer_type, c.cif_status, c.customer_name1
            FROM   STTM_CUSTOMER c
            WHERE  NOT EXISTS (SELECT 1 FROM STTM_CUST_ACCOUNT a
                                WHERE a.cust_no = c.customer_no)
            ORDER BY c.customer_no
        ) WHERE ROWNUM <= 10
    ) LOOP
        p(RPAD(r.customer_no,20)||RPAD(NVL(r.customer_type,'-'),6)||
          RPAD(NVL(r.cif_status,'-'),12)||NVL(SUBSTR(r.customer_name1,1,50),'-'));
    END LOOP;

    sub('5.5 Comptes SANS client (cust_no absent ou inconnu)');
    SELECT COUNT(*) INTO v_n FROM STTM_CUST_ACCOUNT
     WHERE cust_no IS NULL;
    p('Comptes avec CUST_NO NULL                       : '||v_n);
    SELECT COUNT(*) INTO v_n
    FROM   STTM_CUST_ACCOUNT a
    WHERE  a.cust_no IS NOT NULL
      AND  NOT EXISTS (SELECT 1 FROM STTM_CUSTOMER c
                        WHERE c.customer_no = a.cust_no);
    p('Comptes pointant vers un CIF inexistant (orphan): '||v_n);

    sub('5.6 STTM_CUSTOMER vs STTM_CUST_PERSONAL (couverture personnes physiques)');
    SELECT COUNT(*) INTO v_n  FROM STTM_CUSTOMER WHERE customer_type='I';
    SELECT COUNT(*) INTO v_n2 FROM STTM_CUST_PERSONAL;
    p('Clients de type I (Individual)        : '||v_n);
    p('Lignes STTM_CUST_PERSONAL             : '||v_n2);
    SELECT COUNT(*) INTO v_n FROM STTM_CUSTOMER c
     WHERE customer_type='I'
       AND NOT EXISTS (SELECT 1 FROM STTM_CUST_PERSONAL p
                        WHERE p.customer_no = c.customer_no);
    p('Particuliers SANS fiche CUST_PERSONAL : '||v_n);
    SELECT COUNT(*) INTO v_n FROM STTM_CUST_PERSONAL p
     WHERE NOT EXISTS (SELECT 1 FROM STTM_CUSTOMER c
                        WHERE c.customer_no = p.customer_no);
    p('Fiches CUST_PERSONAL orphelines       : '||v_n);

    sub('5.7 STTM_CUSTOMER vs STTM_KYC_MASTER (couverture KYC)');
    SELECT COUNT(*) INTO v_n FROM STTM_CUSTOMER c
     WHERE c.kyc_ref_no IS NULL;
    p('Clients sans KYC_REF_NO                       : '||v_n);
    SELECT COUNT(*) INTO v_n FROM STTM_CUSTOMER c
     WHERE c.kyc_ref_no IS NOT NULL
       AND NOT EXISTS (SELECT 1 FROM STTM_KYC_MASTER k
                        WHERE k.kyc_ref_no = c.kyc_ref_no);
    p('Clients avec KYC_REF_NO mais master inexistant: '||v_n);
    SELECT COUNT(*) INTO v_n FROM STTM_KYC_MASTER k
     WHERE NOT EXISTS (SELECT 1 FROM STTM_CUSTOMER c
                        WHERE c.kyc_ref_no = k.kyc_ref_no);
    p('Lignes KYC_MASTER non rattachees a un client  : '||v_n);

    sub('5.8 Repartition KYC RETAIL vs CORPORATE');
    SELECT COUNT(*) INTO v_n FROM STTM_KYC_RETAIL;     p('STTM_KYC_RETAIL    : '||v_n);
    SELECT COUNT(*) INTO v_n FROM STTM_KYC_CORPORATE;  p('STTM_KYC_CORPORATE : '||v_n);
    -- coherence : un KYC ne devrait apparaitre que dans une seule des deux
    SELECT COUNT(*) INTO v_n FROM STTM_KYC_RETAIL r
     WHERE EXISTS (SELECT 1 FROM STTM_KYC_CORPORATE c
                    WHERE c.kyc_ref_no = r.kyc_ref_no);
    p('KYC present a la fois en RETAIL et CORPORATE (anomalie) : '||v_n);
END;
/

DECLARE
    PROCEDURE p(s IN VARCHAR2 DEFAULT NULL) IS
    BEGIN DBMS_OUTPUT.PUT_LINE(NVL(s,' ')); END;
    PROCEDURE hdr(t IN VARCHAR2) IS
    BEGIN p(''); p(RPAD('=',100,'=')); p(t); p(RPAD('=',100,'=')); END;
    PROCEDURE sub(t IN VARCHAR2) IS
    BEGIN p(''); p('--- '||t||' '||RPAD('-',GREATEST(95-LENGTH(t),3),'-')); END;

    v_n NUMBER;
BEGIN
    --==========================================================================
    -- SECTION 6 - DETECTION D'ANOMALIES
    --==========================================================================
    hdr('SECTION 6 - DETECTION D''ANOMALIES');

    sub('6.1 Doublons sur identifiants clients');
    -- 6.1.a NIU / Unique ID partage par plusieurs CIF
    p('>> Memes UNIQUE_ID_VALUE utilises par plusieurs CUSTOMER_NO :');
    p(RPAD('UNIQUE_ID_NAME',25)||RPAD('UNIQUE_ID_VALUE',30)||
      RPAD('NB_CIF',8)||'CUSTOMER_NOS');
    p(RPAD('-',120,'-'));
    v_n := 0;
    FOR r IN (
        SELECT * FROM (
            SELECT  unique_id_name, unique_id_value,
                    COUNT(DISTINCT customer_no) nb_cif,
                    LISTAGG(customer_no,',') WITHIN GROUP (ORDER BY customer_no) ids
            FROM    STTM_CUSTOMER
            WHERE   unique_id_value IS NOT NULL
            GROUP BY unique_id_name, unique_id_value
            HAVING  COUNT(DISTINCT customer_no) > 1
            ORDER BY 3 DESC
        ) WHERE ROWNUM <= 30
    ) LOOP
        v_n := v_n+1;
        p(RPAD(NVL(r.unique_id_name,'-'),25)||
          RPAD(SUBSTR(r.unique_id_value,1,28),30)||
          RPAD(TO_CHAR(r.nb_cif),8)||SUBSTR(r.ids,1,60));
    END LOOP;
    IF v_n=0 THEN p('(aucun doublon detecte)'); ELSE p('... ('||v_n||' lignes affichees, max 30)'); END IF;

    -- 6.1.b National ID partage
    p('');
    p('>> Memes P_NATIONAL_ID utilises par plusieurs clients :');
    p(RPAD('P_NATIONAL_ID',30)||RPAD('NB_CIF',8)||'CUSTOMER_NOS');
    p(RPAD('-',120,'-'));
    v_n := 0;
    FOR r IN (
        SELECT * FROM (
            SELECT  p_national_id,
                    COUNT(DISTINCT customer_no) nb_cif,
                    LISTAGG(customer_no,',') WITHIN GROUP (ORDER BY customer_no) ids
            FROM    STTM_CUST_PERSONAL
            WHERE   p_national_id IS NOT NULL AND TRIM(p_national_id) IS NOT NULL
            GROUP BY p_national_id
            HAVING  COUNT(DISTINCT customer_no) > 1
            ORDER BY 2 DESC
        ) WHERE ROWNUM <= 30
    ) LOOP
        v_n := v_n+1;
        p(RPAD(SUBSTR(r.p_national_id,1,28),30)||
          RPAD(TO_CHAR(r.nb_cif),8)||SUBSTR(r.ids,1,80));
    END LOOP;
    IF v_n=0 THEN p('(aucun doublon detecte)'); END IF;

    -- 6.1.c Passeport partage
    p('');
    p('>> Memes PASSPORT_NO utilises par plusieurs clients :');
    p(RPAD('PASSPORT_NO',25)||RPAD('NB_CIF',8)||'CUSTOMER_NOS');
    p(RPAD('-',120,'-'));
    v_n := 0;
    FOR r IN (
        SELECT * FROM (
            SELECT  passport_no,
                    COUNT(DISTINCT customer_no) nb_cif,
                    LISTAGG(customer_no,',') WITHIN GROUP (ORDER BY customer_no) ids
            FROM    STTM_CUST_PERSONAL
            WHERE   passport_no IS NOT NULL AND TRIM(passport_no) IS NOT NULL
            GROUP BY passport_no
            HAVING  COUNT(DISTINCT customer_no) > 1
            ORDER BY 2 DESC
        ) WHERE ROWNUM <= 20
    ) LOOP
        v_n := v_n+1;
        p(RPAD(SUBSTR(r.passport_no,1,23),25)||
          RPAD(TO_CHAR(r.nb_cif),8)||SUBSTR(r.ids,1,80));
    END LOOP;
    IF v_n=0 THEN p('(aucun doublon detecte)'); END IF;

    sub('6.2 Doublons potentiels sur (NOM + DATE_OF_BIRTH)');
    p(RPAD('FIRST_NAME',25)||RPAD('LAST_NAME',25)||RPAD('DOB',12)||
      RPAD('NB',6)||'CUSTOMER_NOS');
    p(RPAD('-',120,'-'));
    v_n := 0;
    FOR r IN (
        SELECT * FROM (
            SELECT  UPPER(TRIM(first_name)) fn,
                    UPPER(TRIM(last_name))  ln,
                    date_of_birth dob,
                    COUNT(*) nb,
                    LISTAGG(customer_no,',') WITHIN GROUP (ORDER BY customer_no) ids
            FROM    STTM_CUST_PERSONAL
            WHERE   first_name IS NOT NULL AND last_name IS NOT NULL
              AND   date_of_birth IS NOT NULL
            GROUP BY UPPER(TRIM(first_name)), UPPER(TRIM(last_name)), date_of_birth
            HAVING  COUNT(*) > 1
            ORDER BY 4 DESC
        ) WHERE ROWNUM <= 30
    ) LOOP
        v_n := v_n+1;
        p(RPAD(SUBSTR(r.fn,1,23),25)||RPAD(SUBSTR(r.ln,1,23),25)||
          RPAD(TO_CHAR(r.dob,'YYYY-MM-DD'),12)||
          RPAD(TO_CHAR(r.nb),6)||SUBSTR(r.ids,1,60));
    END LOOP;
    IF v_n=0 THEN p('(aucun doublon detecte)'); END IF;

    sub('6.3 Doublons sur comptes');
    p('>> IBAN utilise par plusieurs comptes :');
    p(RPAD('IBAN_AC_NO',35)||RPAD('NB',6)||'CUST_AC_NOS');
    p(RPAD('-',120,'-'));
    v_n := 0;
    FOR r IN (
        SELECT * FROM (
            SELECT  iban_ac_no, COUNT(*) nb,
                    LISTAGG(cust_ac_no,',') WITHIN GROUP (ORDER BY cust_ac_no) acs
            FROM    STTM_CUST_ACCOUNT
            WHERE   iban_ac_no IS NOT NULL
            GROUP BY iban_ac_no
            HAVING  COUNT(*) > 1
            ORDER BY 2 DESC
        ) WHERE ROWNUM <= 20
    ) LOOP
        v_n := v_n+1;
        p(RPAD(SUBSTR(r.iban_ac_no,1,33),35)||
          RPAD(TO_CHAR(r.nb),6)||SUBSTR(r.acs,1,60));
    END LOOP;
    IF v_n=0 THEN p('(aucun doublon IBAN)'); END IF;

    p('');
    p('>> ALT_AC_NO utilise par plusieurs comptes :');
    p(RPAD('ALT_AC_NO',25)||RPAD('NB',6)||'CUST_AC_NOS');
    p(RPAD('-',120,'-'));
    v_n := 0;
    FOR r IN (
        SELECT * FROM (
            SELECT  alt_ac_no, COUNT(*) nb,
                    LISTAGG(cust_ac_no,',') WITHIN GROUP (ORDER BY cust_ac_no) acs
            FROM    STTM_CUST_ACCOUNT
            WHERE   alt_ac_no IS NOT NULL
            GROUP BY alt_ac_no
            HAVING  COUNT(*) > 1
            ORDER BY 2 DESC
        ) WHERE ROWNUM <= 20
    ) LOOP
        v_n := v_n+1;
        p(RPAD(SUBSTR(r.alt_ac_no,1,23),25)||
          RPAD(TO_CHAR(r.nb),6)||SUBSTR(r.acs,1,80));
    END LOOP;
    IF v_n=0 THEN p('(aucun doublon ALT_AC_NO)'); END IF;

    sub('6.4 Champs critiques manquants - resume');
    SELECT COUNT(*) INTO v_n FROM STTM_CUSTOMER
     WHERE customer_name1 IS NULL OR TRIM(customer_name1) IS NULL;
    p('STTM_CUSTOMER         sans CUSTOMER_NAME1     : '||v_n);
    SELECT COUNT(*) INTO v_n FROM STTM_CUSTOMER WHERE unique_id_value IS NULL;
    p('STTM_CUSTOMER         sans UNIQUE_ID_VALUE    : '||v_n);
    SELECT COUNT(*) INTO v_n FROM STTM_CUSTOMER WHERE nationality IS NULL;
    p('STTM_CUSTOMER         sans NATIONALITY        : '||v_n);
    SELECT COUNT(*) INTO v_n FROM STTM_CUST_PERSONAL WHERE date_of_birth IS NULL;
    p('STTM_CUST_PERSONAL    sans DATE_OF_BIRTH      : '||v_n);
    SELECT COUNT(*) INTO v_n FROM STTM_CUST_PERSONAL
     WHERE p_national_id IS NULL AND passport_no IS NULL;
    p('STTM_CUST_PERSONAL    sans NID ni PASSPORT    : '||v_n);
    SELECT COUNT(*) INTO v_n FROM STTM_CUST_ACCOUNT WHERE cust_no IS NULL;
    p('STTM_CUST_ACCOUNT     sans CUST_NO            : '||v_n);
    SELECT COUNT(*) INTO v_n FROM STTM_CUST_ACCOUNT WHERE ac_open_date IS NULL;
    p('STTM_CUST_ACCOUNT     sans AC_OPEN_DATE       : '||v_n);

    sub('6.5 Coherences logiques');
    -- DOB futur ou trop ancien
    SELECT COUNT(*) INTO v_n FROM STTM_CUST_PERSONAL WHERE date_of_birth > SYSDATE;
    p('Date de naissance dans le FUTUR              : '||v_n);
    SELECT COUNT(*) INTO v_n FROM STTM_CUST_PERSONAL
     WHERE date_of_birth < TO_DATE('1900-01-01','YYYY-MM-DD');
    p('Date de naissance avant 1900                 : '||v_n);
    SELECT COUNT(*) INTO v_n FROM STTM_CUST_PERSONAL
     WHERE MONTHS_BETWEEN(SYSDATE,date_of_birth)/12 > 110;
    p('Age > 110 ans                                : '||v_n);
    -- Compte ouvert dans le futur
    SELECT COUNT(*) INTO v_n FROM STTM_CUST_ACCOUNT WHERE ac_open_date > SYSDATE;
    p('Comptes avec AC_OPEN_DATE dans le FUTUR      : '||v_n);
    -- Passeport expire mais utilise comme ID actif
    SELECT COUNT(*) INTO v_n FROM STTM_CUST_PERSONAL
     WHERE ppt_exp_date IS NOT NULL AND ppt_exp_date < SYSDATE
       AND passport_no IS NOT NULL;
    p('Passeport expire et toujours renseigne       : '||v_n);
    -- Status incoherent : compte non autorise mais ouvert
    SELECT COUNT(*) INTO v_n FROM STTM_CUST_ACCOUNT
     WHERE auth_stat='U' AND record_stat='O';
    p('Comptes Open mais Unauthorized               : '||v_n);
END;
/
