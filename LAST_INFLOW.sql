select * from mgodi_msisdn_prof;

---------------------------------------------------------------

CREATE TABLE BLOCKED_CUSTOMERS_STATUS PARALLEL (DEGREE 64) AS
SELECT  DISTINCT CUSTOMER_ID,
       MC_MSISDN,
       C_DATA_VALUE MC_STATUS,
       MCA_CLOSE_DATE,
       MPESA_BALANCE 
FROM mgodi_msisdn_prof 
LEFT JOIN ODS.STG_MLC_MDF_LOOKUP_CONFIG
ON MC_STATUS = C_DATA_KEY
AND C_CONFIG_NAME = 'Identity Status';

SELECT * FROM BLOCKED_CUSTOMERS_STATUS;

---------------------------------------------------------

CREATE TABLE CUSTOMER_INFLOW PARALLEL (DEGREE 64) AS
SELECT DISTINCT MPT_RECEIPT_NUMBER,
       MPT_TRANSACTION_DATE,
       MPT_APARTY_NORM,
       MPT_BPARTY_NORM,
       MPT_RT_ID,
       MPT_TRANSACTION_VALUE,
       MPT_FEE,
       MPT_APARTY_ACCOUNT,
       MPT_BPARTY_ACCOUNT 
FROM ODS.FCT_MPT_MPESA_TRANSACTION
WHERE MPT_TRANSACTION_DATE >= ADD_MONTHS(TRUNC(SYSDATE,'MM'),-3)
AND MPT_TRANSACTION_DATE < TRUNC(SYSDATE)
AND MPT_BPARTY_ACCOUNT = '-1';

select * from CUSTOMER_INFLOW;

---------------------------------------------------------------

DROP TABLE CUSTOMER_INFLOW_PROFILE PURGE;


CREATE TABLE CUSTOMER_INFLOW_PROFILE PARALLEL (DEGREE 64) AS
SELECT DISTINCT A.*, 
       MAE_SHORTCODE_MSISDN MSISDN,
       TO_CHAR(MAE_ACCOUNT_NO) ACCOUNT_NO
FROM CUSTOMER_INFLOW A
LEFT JOIN ODS.STG_MAE_MDF_ACCOUNT_ENTRY
ON MPT_RECEIPT_NUMBER = MAE_TRANS_INDEX
WHERE MAE_FUNDS_TYPE = '1' 
AND MAE_IDENTITY_TYPE = '1000'
AND MAE_ACCOUNT_TYPE_ID = '10011'
AND MAE_PAID_IN_AMOUNT > 0;

------------------------------------

SELECT MPT_RECEIPT_NUMBER,COUNT(MPT_RECEIPT_NUMBER) FROM CUSTOMER_INFLOW_PROFILE
GROUP BY MPT_RECEIPT_NUMBER
HAVING COUNT(MPT_RECEIPT_NUMBER) > 1;

---------------------------------------

CREATE TABLE MGODI_MSISDN_TRANS PARALLEL (DEGREE 64) AS
SELECT DISTINCT CUSTOMER_ID,
       MC_MSISDN,
       MC_STATUS,
       MCA_CLOSE_DATE,
       MPESA_BALANCE,
       MPT_RECEIPT_NUMBER,
       MPT_TRANSACTION_DATE,
       MPT_TRANSACTION_VALUE,
       MPT_RT_ID
FROM BLOCKED_CUSTOMERS_STATUS
LEFT JOIN CUSTOMER_INFLOW_PROFILE
ON CUSTOMER_ID = ACCOUNT_NO;


SELECT * FROM mgodi_msisdn_trans;

-------------------------------------------------

DROP TABLE MGODI_MSISDN_LAST_TRANS PURGE;

CREATE TABLE MGODI_MSISDN_LAST_TRANS PARALLEL (DEGREE 64) AS
WITH DATA AS (
SELECT DISTINCT CUSTOMER_ID,
       MAX(MPT_RECEIPT_NUMBER) LAST_RECEIPT
FROM MGODI_MSISDN_TRANS
GROUP BY CUSTOMER_ID
)
SELECT DISTINCT A.CUSTOMER_ID,
       LAST_RECEIPT LAST_INFLOW_RECEIPT,
       MPT_TRANSACTION_DATE LAST_INFLOW_DATE,
       MPT_TRANSACTION_VALUE LAST_INFLOW_VALUE,
       MPT_RT_ID
FROM DATA A
LEFT JOIN MGODI_MSISDN_TRANS
ON LAST_RECEIPT = MPT_RECEIPT_NUMBER;

select * from MGODI_MSISDN_LAST_TRANS;

--------------------------------------------

CREATE TABLE MGODI_MSISDN_LAST_TRANS1 PARALLEL (DEGREE 64) AS
SELECT DISTINCT CUSTOMER_ID,
       LAST_INFLOW_RECEIPT,
       LAST_INFLOW_DATE,
       LAST_INFLOW_VALUE,
       RT_CODE LAST_TRANSACTION_TYPE 
FROM MGODI_MSISDN_LAST_TRANS
LEFT JOIN INSIGHT.F_RT_RECORD_TYPE
ON MPT_RT_ID = RT_SEQID;

SELECT * FROM MGODI_MSISDN_LAST_TRANS1;

------------------------------------------------------

CREATE TABLE MGODI_MSISDN_TRANSANCTION PARALLEL (DEGREE 64) AS
SELECT DISTINCT A.*,
       LAST_INFLOW_RECEIPT,
       LAST_INFLOW_DATE,
       LAST_INFLOW_VALUE,
       LAST_TRANSACTION_TYPE 
FROM MGODI_MSISDN_TRANS A
LEFT JOIN MGODI_MSISDN_LAST_TRANS1 B
ON A.CUSTOMER_ID = B.CUSTOMER_ID;

SELECT * FROM MGODI_MSISDN_TRANSANCTION;

--------------------------------------------------------

CREATE TABLE MGODI_MSISDN_FINAL PARALLEL (DEGREE 64) AS
SELECT * FROM (
SELECT TO_CHAR(MPT_TRANSACTION_DATE,'MON') DAY_DATE,
       CUSTOMER_ID,
       MC_STATUS,
       MCA_CLOSE_DATE,
       MPESA_BALANCE,
       LAST_INFLOW_DATE,
       LAST_INFLOW_RECEIPT,
       LAST_INFLOW_VALUE,
       LAST_TRANSACTION_TYPE,
       MPT_RECEIPT_NUMBER,
       MPT_TRANSACTION_VALUE      
FROM MGODI_MSISDN_TRANSANCTION
)
PIVOT (
    COUNT(DISTINCT MPT_RECEIPT_NUMBER) VOLUME,
    SUM(MPT_TRANSACTION_VALUE) VALUE
  FOR DAY_DATE IN ('SEP' SEP,'OCT' OCT,'NOV' NOV,'DEC' DEC,'JAN' JAN)
);


SELECT * FROM MGODI_MSISDN_FINAL;