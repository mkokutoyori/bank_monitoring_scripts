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
