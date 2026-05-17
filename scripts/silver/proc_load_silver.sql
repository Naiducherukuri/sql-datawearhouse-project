CREATE OR ALTER PROCEDURE silver.load_silver AS
BEGIN
DECLARE @start_time DATETIME,@end_time DATETIME,@batch_start_time DATETIME,@batch_end_time DATETIME
BEGIN TRY
SET @batch_start_time = GETDATE()
PRINT '============================================';
PRINT 'loading tables in silver layer';
PRINT '============================================';


PRINT '--------------------------------------------'
PRINT 'loading crm tables';
PRINT '--------------------------------------------'
SET @start_time = GETDATE();
PRINT '<< Trucating table : silver.crm_cust_info >>'
TRUNCATE TABLE silver.crm_cust_info
PRINT '<< inserting the data into: silver.crm_cust_info >>'
INSERT INTO silver.crm_cust_info(
    cst_id,
    cst_key,
    cst_firstname,
    cst_lastname,
    cst_marital_status,
    cst_gndr,
    cst_create_date)
SELECT 
cst_id,
cst_key,
TRIM(cst_firstname) AS cst_firstname,
TRIM(cst_lastname) AS cst_lastname,
CASE
	WHEN UPPER(TRIM(cst_gender)) ='M' THEN 'MALE'
	WHEN UPPER(TRIM(cst_gender)) = 'F' THEN 'FEMALE'
    ELSE 'N/A'
END cst_gender,
CASE 
	WHEN UPPER(TRIM(cst_material_status)) = 'M' THEN 'married'
	WHEN UPPER(TRIM(cst_material_status)) ='S' THEN 'single'
	ELSE 'N/A'
END cst_material_status,
cst_create_date
FROM 
(SELECT *,
ROW_NUMBER() OVER(PARTITION BY cst_id ORDER BY cst_create_date DESC) AS flag_last
FROM bronze.crm_cust_info) t

WHERE flag_last = 1
SET @end_time = GETDATE();

PRINT 'load duration ' + CAST(DATEDIFF(second,@start_time,@end_time) AS NVARCHAR) + 'seconds';
PRINT '--------------';
SET @start_time = GETDATE();
PRINT '<< Trucating table : silver.crm_prd_info >>'
TRUNCATE TABLE silver.crm_prd_info
PRINT '<< inserting the data into: silver.crm_cust_info >>'
INSERT INTO silver.crm_prd_info (
prd_id,
cat_id,
prd_key,
prd_nm,
prd_cost,
prd_line,
prd_start_dt,
prd_end_dt
)
SELECT
prd_id,
REPLACE(SUBSTRING(prd_key, 1, 5), '-', '_') AS cat_id, -- Extract category ID
SUBSTRING(prd_key, 7, LEN(prd_key)) AS prd_key,        -- Extract product key
prd_nm,
ISNULL(prd_cost, 0) AS prd_cost,
CASE 
	WHEN UPPER(TRIM(prd_line)) = 'M' THEN 'Mountain'
	WHEN UPPER(TRIM(prd_line)) = 'R' THEN 'Road'
	WHEN UPPER(TRIM(prd_line)) = 'S' THEN 'Other Sales'
	WHEN UPPER(TRIM(prd_line)) = 'T' THEN 'Touring'
    ELSE 'n/a'
END AS prd_line, -- Map product line codes to descriptive values
	CAST(prd_start_dt AS DATE) AS prd_start_dt,
	CAST(
	LEAD(prd_start_dt) OVER (PARTITION BY prd_key ORDER BY prd_start_dt) - 1 
	AS DATE
	) AS prd_end_dt -- Calculate end date as one day before the next start date
FROM bronze.crm_prd_info;
SET @end_time = GETDATE();

PRINT 'load duration ' + CAST(DATEDIFF(second,@start_time,@end_time) AS NVARCHAR) + 'seconds';
PRINT '--------------';
SET @start_time = GETDATE();
PRINT '<< Trucating table : silver.crm_sales_details >>'
TRUNCATE TABLE silver.crm_sales_details
PRINT '<< inserting the data into: silver.crm_sales_details >>'
INSERT INTO silver.crm_sales_details(
    sls_odr_num,
    sls_prd_key,     
    sls_cst_id,    
    sls_order_dt,     
    sls_ship_dt,      
    sls_due_dt,     
    sls_sales,        
    sls_quantity,     
    sls_price
)
SELECT 
sls_odr_num,
sls_prd_key,
sls_cst_id,
CASE WHEN sls_order_dt = 0 OR LEN(sls_order_dt) != 8 OR sls_order_dt < 1 
	THEN NULL
	ELSE CAST(CAST(sls_order_dt AS VARCHAR) AS DATE)
END sls_order_dt,
CASE WHEN sls_ship_dt = 0 OR sls_ship_dt < 1 
	THEN NULL
	ELSE CAST(CAST(sls_ship_dt AS VARCHAR) AS DATE)
END sls_ship_dt,
CASE WHEN sls_due_dt = 0 OR sls_due_dt < 1 
	THEN NULL
	ELSE CAST(CAST(sls_due_dt AS VARCHAR) AS DATE)
END sls_due_dt,
CASE WHEN sls_sales IS NULL OR sls_sales <= 0 OR sls_sales != sls_quantity * ABS(sls_price)
THEN sls_quantity * ABS(sls_price) 
ELSE sls_sales
END AS sls_sales,
sls_quantity,
CASE WHEN sls_price IS NULL OR sls_price <= 0
 THEN sls_sales / NULLIF(sls_quantity,0)
 ELSE sls_price
 END sls_price
 FROM bronze.crm_sales_details;
 SET @end_time = GETDATE();
PRINT 'load duration ' + CAST(DATEDIFF(second,@start_time,@end_time) AS NVARCHAR) + 'seconds';
PRINT '--------------';

PRINT '------------------------------------------------';
PRINT 'Loading ERP Tables';
PRINT '------------------------------------------------';

SET @start_time = GETDATE();
 PRINT '<< Trucating table : silver.erp_cust_az12 >>'
 TRUNCATE TABLE silver.erp_cust_az12
 PRINT '<< insering data into: silver.silver.erp_cust_az12 >>'
 INSERT INTO silver.erp_cust_az12 (
cid,
bdate,
gen
)
SELECT
CASE
	WHEN cid LIKE 'NAS%' THEN SUBSTRING(cid, 4, LEN(cid)) -- Remove 'NAS' prefix if present
	ELSE cid
END AS cid, 
CASE
 WHEN bdate > GETDATE() THEN NULL
ELSE bdate
END AS bdate, -- Set future birthdates to NULL
CASE
WHEN UPPER(TRIM(gen)) IN ('F', 'FEMALE') THEN 'Female'
WHEN UPPER(TRIM(gen)) IN ('M', 'MALE') THEN 'Male'
ELSE 'n/a'
END AS gen -- Normalize gender values and handle unknown cases
FROM bronze.erp_cust_az12;
 SET @end_time = GETDATE();
PRINT 'load duration ' + CAST(DATEDIFF(second,@start_time,@end_time) AS NVARCHAR) + 'seconds';
PRINT '--------------';
SET @start_time = GETDATE();
PRINT '<< Trucating table : silver.erp_loc_a101 >>'
TRUNCATE TABLE silver.erp_loc_a101
PRINT '<< Inserting data into : silver.erp_loc_a101 >>'
INSERT INTO silver.erp_loc_a101 (cid,cntry)
SELECT 
REPLACE(cid,'-','') cid,
CASE 
	WHEN TRIM(cntry) = 'DE' THEN 'Germany'
	WHEN TRIM(cntry) = '' OR cntry IS NULL THEN 'n/a'
	WHEN TRIM(cntry) IN ('US','USA') THEN 'United states'
	ELSE TRIM(cntry)
END AS cntry
FROM bronze.erp_loc_a101;
 SET @end_time = GETDATE();
PRINT 'load duration ' + CAST(DATEDIFF(second,@start_time,@end_time) AS NVARCHAR) + 'seconds';
PRINT '--------------';
SET @start_time = GETDATE();
PRINT '<< Trucating table : silver.erp_px_cat_g1v2; >>'
TRUNCATE TABLE silver.erp_px_cat_g1v2;
PRINT '<< Insering data into : silver.erp_px_cat_g1v2; >>'
INSERT INTO silver.erp_px_cat_g1V2
(id,
cat,
subcat,
maintenance)
SELECT 
id,
cat,
subcat,
maintenence
FROM bronze.erp_px_cat_g1V2
SET @end_time = GETDATE();
PRINT 'load duration ' + CAST(DATEDIFF(second,@start_time,@end_time) AS NVARCHAR) + 'seconds';
PRINT '--------------';
SET @batch_end_time = GETDATE();
PRINT 'loading silver layer is completed';
PRINT 'load duration time is ' + CAST(DATEDIFF(second,@batch_start_time,@batch_end_time) AS NVARCHAR) + ' seconds';
END TRY
BEGIN CATCH
PRINT '=====================================================================================';
PRINT 'error occured during loading silver layer';
PRINT 'ERROR MEESEGE' + ERROR_MESSAGE();
PRINT 'ERROR MEESEGE' + CAST (ERROR_NUMBER() AS NVARCHAR);
PRINT 'ERROR MEESEGE' + CAST (ERROR_STATE()  AS NVARCHAR);
PRINT '=====================================================================================';
END CATCH
END

