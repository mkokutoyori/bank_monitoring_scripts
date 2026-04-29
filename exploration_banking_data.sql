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
