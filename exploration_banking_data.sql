--==============================================================================
-- Script d'exploration : cartographie des donnees Clients / Comptes / KYC
-- Cible : Oracle 12c (FLEXCUBE / core banking)
-- Mode  : SELECT only - aucune modification de donnees
-- Auteur: Data Exploration
--==============================================================================
SET LINESIZE 300
SET PAGESIZE 200
SET SERVEROUTPUT ON SIZE UNLIMITED
SET LONG 32000
COLUMN TABLE_NAME       FORMAT A35
COLUMN COLUMN_NAME      FORMAT A35
COLUMN DATA_TYPE        FORMAT A15
COLUMN CONSTRAINT_NAME  FORMAT A30
COLUMN OWNER            FORMAT A15
COLUMN COMMENTS         FORMAT A60
COLUMN VAL              FORMAT A40
COLUMN DESCRIPTION      FORMAT A60

PROMPT
PROMPT ##############################################################################
PROMPT # SECTION 1 - INVENTAIRE DES TABLES PERTINENTES
PROMPT ##############################################################################

-- 1.1 Tables candidates par mot-cle (CUST/CUSTOMER/CIF/ACCOUNT/ACCT/KYC/DOC)
PROMPT
PROMPT --- 1.1 Tables candidates (USER_TABLES) ---
SELECT  t.table_name,
        t.num_rows                                AS num_rows_stats,
        t.last_analyzed,
        tc.comments                               AS table_comment
FROM    user_tables       t
LEFT JOIN user_tab_comments tc ON tc.table_name = t.table_name
WHERE   REGEXP_LIKE(t.table_name,'CUST|CIF|ACCOUNT|ACCT|KYC|DOC','i')
ORDER BY t.num_rows DESC NULLS LAST;

-- 1.2 Vues candidates (souvent les ecrans front s'appuient dessus)
PROMPT
PROMPT --- 1.2 Vues candidates (USER_VIEWS) ---
SELECT  v.view_name,
        vc.comments AS view_comment
FROM    user_views          v
LEFT JOIN user_tab_comments vc ON vc.table_name = v.view_name
WHERE   REGEXP_LIKE(v.view_name,'CUST|CIF|ACCOUNT|ACCT|KYC|DOC','i')
ORDER BY v.view_name;

-- 1.3 Synonymes pointant vers ces tables/vues
PROMPT
PROMPT --- 1.3 Synonymes ---
SELECT  synonym_name, table_owner, table_name
FROM    user_synonyms
WHERE   REGEXP_LIKE(table_name,'CUST|CIF|ACCOUNT|ACCT|KYC|DOC','i')
ORDER BY synonym_name;

-- 1.4 Comptage reel (utile car USER_TABLES.NUM_ROWS depend des stats)
PROMPT
PROMPT --- 1.4 Comptage reel des tables cibles ---
SELECT 'STTM_CUSTOMER'              AS tbl, COUNT(*) AS nb FROM STTM_CUSTOMER             UNION ALL
SELECT 'STTM_CUST_PERSONAL'         , COUNT(*)         FROM STTM_CUST_PERSONAL        UNION ALL
SELECT 'STTM_CUST_ACCOUNT'          , COUNT(*)         FROM STTM_CUST_ACCOUNT         UNION ALL
SELECT 'STTB_ACCOUNT'               , COUNT(*)         FROM STTB_ACCOUNT              UNION ALL
SELECT 'STTM_KYC_MASTER'            , COUNT(*)         FROM STTM_KYC_MASTER           UNION ALL
SELECT 'STTM_KYC_RETAIL'            , COUNT(*)         FROM STTM_KYC_RETAIL           UNION ALL
SELECT 'STTM_KYC_CORPORATE'         , COUNT(*)         FROM STTM_KYC_CORPORATE        UNION ALL
SELECT 'STTM_KYC_CORP_KEYPERSONS'   , COUNT(*)         FROM STTM_KYC_CORP_KEYPERSONS  UNION ALL
SELECT 'STTM_ACCOUNT_CLASS'         , COUNT(*)         FROM STTM_ACCOUNT_CLASS        UNION ALL
SELECT 'STTM_CUSTOMER_CAT'          , COUNT(*)         FROM STTM_CUSTOMER_CAT         UNION ALL
SELECT 'CLTB_ACCOUNT_APPS_MASTER'   , COUNT(*)         FROM CLTB_ACCOUNT_APPS_MASTER  UNION ALL
SELECT 'CLTB_ACCOUNT_COMPONENTS'    , COUNT(*)         FROM CLTB_ACCOUNT_COMPONENTS   UNION ALL
SELECT 'CLTB_ACCOUNT_SCHEDULES'     , COUNT(*)         FROM CLTB_ACCOUNT_SCHEDULES
ORDER BY 2 DESC;
