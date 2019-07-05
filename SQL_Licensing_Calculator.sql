USE [master]
GO

SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

CREATE PROCEDURE [dbo].[sp_licensingcalculator]

/*
 Created by Dustin Dorsey -- https://dustindorsey.com/sql-licensing-calculator/ 
 Description: This script allows you calculate your costs for licensing while taking into account the variables associated with licensing. Additionally,
 this script will analyze your builds and let you know if there is anything that you made need to be aware of. 

 v1.0 - This script was last updated on 5/16/2019

 DISCLAIMER: By using this script you agree to do so at your own risk and understand this is not something created by or representative of Microsoft. I highly encourage your to read 
 through the SQL licensing guides and continue working with your licensing providers. Based on years of experience, working with Microsoft and licensed re-sellers on licensing and careful 
 review of the licensing guides I believe the information contained in this is correct, however, its possible something could be wrong. My intention is not to deceive anyone with any misinformation 
 and will gladly receive feedback and update this as information is verified. This tool is not a replacement for determining exact costs and may not cover everything specific to your agreement, 
 rather it is a tool that can be used to help in your decision making.

 If you discover any issues or have suggestions on ways to make this better, please email me at Dorsey.Dustin@att.net 
*/


/* How you want to license */
 @ServerType NVARCHAR(256) = NULL				-- Physical, VM, Host, Container
 ,@LicenseMethod NVARCHAR(256) = NULL			-- CAL or Core
 ,@SQLEdition NVARCHAR(256) = NULL				-- Enterprise, Standard, Enterprise, Developer
 ,@SQLVersion NVARCHAR(12) = NULL				-- 2000, 2005, 2008, 2008 R2, 2012, 2014, 2016, 2017, 2019 
 ,@SoftwareAssurance NVARCHAR(256) = NULL		-- Y or N
 ,@HighAvailability NVARCHAR(256)= NULL			-- Cluster, AG, Mirroring, Replication, LogShipping
 ,@MaxMemoryMB int = NULL

/* Cores */
 ,@CoreNumber SMALLINT = NULL					-- Total number of physical cores
 ,@CoreLicenseCost DECIMAL(15,2) = NULL			-- If cost is known enter here, otherwise it will use retail\estimated cost
 ,@CoreSACost DECIMAL(15,2) = NULL				-- If cost is known enter here, otherwise it will use retail\estimated cost

/* CALS */
 ,@CALnumber INT = NULL							-- Number of CAL licenses.
 ,@CALServerLicenseCost DECIMAL(15,2) = NULL	-- If cost is known enter here, otherwise it will use retail\estimated cost
 ,@CALCost DECIMAL(15,2) = NULL					-- If cost is known enter here, otherwise it will use retail\estimated cost
 ,@CALSACost DECIMAL(10,2) = NULL				-- If cost is known enter here, otherwise it will use retail\estimated cost

/* Override licensing logic */
 ,@Override BIT = 0								-- Set to 1 if you want to ignore all rules and checks

AS 

SET NOCOUNT ON

/* MSRP\Estimated costs */
DECLARE @MSRPStndCoreLicenseCost DECIMAL(15,2)
DECLARE @MSRPEntCoreLicenseCost DECIMAL(15,2)
DECLARE @EstimatedCoreSAPercent DECIMAL(3,2)
DECLARE @MSRPCALServerLicenseCost DECIMAL(15,2)
DECLARE @MSRPCALCost DECIMAL(15,2)
DECLARE @EstimatedCALSAPercent DECIMAL(3,2)

/* Currency (Currently, represented in US dollars) */

SET @MSRPStndCoreLicenseCost = 3717
SET @MSRPEntCoreLicenseCost = 14256
SET @EstimatedCoreSAPercent = 0.3
SET @MSRPCALServerLicenseCost = 930
SET @MSRPCALCost = 209
SET @EstimatedCALSAPercent = 0.25

/* Error handling */

IF ISNULL(@ServerType,'') not in ('VM','Host','Physical','Container') 
BEGIN 
RAISERROR('You have entered an invalid value for @ServerType. Please use VM, Host, Physical or Container', 16,16)
RETURN
END

IF ISNULL(@LicenseMethod,'') not in ('Core','CAL') 
BEGIN 
RAISERROR('You have entered an invalid value for @LicenseMethod. Please use Core or CAL', 16,16)
RETURN
END

IF ISNULL(@SQLEdition,'') not in ('Express','Standard','Enterprise','Developer') 
BEGIN 
RAISERROR('You have entered an invalid value for @SQLEdition. Please use Express, Developer, Standard or Enterprise', 16,16)
RETURN
END

IF ISNULL(@SQLVersion,'') not in ('2000', '2005','2008','2008 R2','2012','2014','2016','2017','2019')
BEGIN 
RAISERROR('You have inputed an invalid value for @SQLVersion, Please try again.
The only allowable values are 2000, 2005, 2008, 2008 R2, 2012, 2014, 2016, 2017, 2019', 16,16)
RETURN
END 

IF ISNULL(@SoftwareAssurance,'') not in ('Y','N') 
BEGIN 
RAISERROR('You have inputed an invalid value for @SoftwareAssurance. Please type Y if you want to include software assurance or N if you do not.', 16,16)
RETURN
END

IF @ServerType = 'Host' and @LicenseMethod = 'CAL'
BEGIN 
RAISERROR('You cannot license a Host with CALS', 16,16)
RETURN
END

IF @ServerType != 'Host' and @CALnumber IS NULL and @LicenseMethod = 'CAL'
BEGIN 
RAISERROR('You have elected to license by CALS, yet you did not enter the number of CALS needed', 16,16)
RETURN
END

IF @CoreNumber IS NULL and @LicenseMethod = 'Core'
BEGIN 
RAISERROR('You have elected to license by Cores, yet you did not enter the number of Cores needed', 16,16)
RETURN
END

IF @HighAvailability not in ('AG','Cluster','Mirroring','LogShipping')
BEGIN 
RAISERROR('You have entered an invalid value for @HighAvailability, please use AG, Cluster, Mirroring, or LogShipping', 16,16)
RETURN
END

IF @HighAvailability is not null and @ServerType = 'Host' 
BEGIN 
RAISERROR('You have entered a value for @HighAvailability, but you are licensing by hosts', 16,16)
RETURN
END

IF @HighAvailability = 'AG' and  @SQLVersion in ('2000', '2005','2008','2008 R2') and @ServerType != 'Host' 
BEGIN 
RAISERROR('Availibility Groups was not made available until SQL 2012. You will need a newer version to be able to run this', 16,16)
RETURN
END

IF @HighAvailability in ('AG','Cluster','Mirroring') and @SQLEdition = 'Express' 
BEGIN 
RAISERROR('Availibility groups, clustering and mirroring are not available in Express edition', 16,16)
RETURN
END

IF @ServerType = 'Host' and @SQLEdition in ('Express','Developer') 
BEGIN 
RAISERROR('You cannot license a host with Developer or Express edition', 16,16)
RETURN
END

IF @HighAvailability = 'AG' and @SQLEdition = 'Standard' and ISNULL(@SQLVersion,'') in ('2000', '2005','2008','2008 R2','2012','2014') 
BEGIN 
RAISERROR('Availiability groups was released for Standard edition in SQL 2016', 16,16)
RETURN
END

IF @ServerType = 'Host' and @SQLEdition != 'Enterprise' and @LicenseMethod != 'CAL' and @Override = 0
BEGIN 
RAISERROR('Enterprise Edition is required to license hosts', 16,16)
RETURN
END

IF @LicenseMethod = 'CAL' and @SQLEdition != 'Standard' and @ServerType != 'Host' and @CALnumber IS NOT NULL
and @CALServerLicenseCost IS NULL and @CALCost IS NULL and @CALCost IS NULL and @Override = 0
BEGIN 
RAISERROR('With the latest licensing model you can only license using CALs with Standard Edition. However, if you have CALs from earlier
versions you may still be able to use them, but you need to work with your licensing rep. You can still use the Licensing Calculator
to determine cost, however, you must provide values for @CALServerLicenseCost, @CALCost and @CALCost', 16,16)
RETURN
END

/* If License method is core then clear values for CAL. This prevents warnings from showing up */
IF @LicenseMethod = 'Core'
BEGIN 
SET @CALnumber = NULL
SET @CALServerLicenseCost = NULL
SET @CALCost = NULL
SET @CALSACost = NULL
END 

/* If license method is CAL then clear values for Core. This prevents warnings from showing up */
IF @LicenseMethod = 'CAL'
BEGIN 
SET @CoreLicenseCost = NULL
SET @CoreSACost = NULL
END

/* If Express or Developer selected then 0 out the costs */
IF @SQLEdition in ('Express','Developer')
BEGIN 
SET @CALnumber = 0
SET @CALServerLicenseCost = 0
SET @CALCost = 0
SET @CALSACost = 0
SET @CoreLicenseCost = 0
SET @CoreSACost = 0
END 

/* Create temp tables to contain data */                       

IF OBJECT_ID('tempdb..#LicenseCostForCores') IS NOT NULL DROP TABLE #LicenseCostForCores

CREATE TABLE #LicenseCostForCores
(Server_Type NVARCHAR(256),
License_Type NVARCHAR(256),
SQL_Version NVARCHAR(12), 
SQL_Edition NVARCHAR(256),
Licenses_Needed SMALLINT,
License_Cost DECIMAL(15,2),
SA_yearly_cost DECIMAL(15,2),
Total_year1_cost DECIMAL(15,2))

IF OBJECT_ID('tempdb..#LicenseCostForCALs') IS NOT NULL DROP TABLE #LicenseCostForCALs

CREATE TABLE #LicenseCostForCALs
(Server_Type NVARCHAR(256),
License_Type NVARCHAR(256),
SQL_Version NVARCHAR(256), 
SQL_Edition NVARCHAR(256),
CALS_Needed INT,
CAL_Server_Cost DECIMAL(15,2),
CAL_Cost DECIMAL(15,2),
SA_yearly_cost DECIMAL(15,2),
Total_year1_cost DECIMAL(15,2))

IF OBJECT_ID('tempdb..#LicenseInformation') IS NOT NULL DROP TABLE #LicenseInformation

CREATE TABLE #LicenseInformation
(Message_Type NVARCHAR(256),
[Message] NVARCHAR(2000),
Link NVARCHAR(500))

/* Check to make sure core count is even number, if not round up 1 (Licensing is sold in 2-packs) */
DECLARE @EvenPhysicalCoreNumber INT
SELECT @EvenPhysicalCoreNumber = CASE @CoreNumber % 2 WHEN 1 THEN @CoreNumber + 1 ELSE @CoreNumber END

/* Log memory\CPU thresholds for each version */

IF OBJECT_ID('tempdb..#SQLVersionResourceLimitations') IS NOT NULL DROP TABLE #SQLVersionResourceLimitations

CREATE TABLE #SQLVersionResourceLimitations
(SQL_Version NVARCHAR(256),
SQL_Edition NVARCHAR(256),
Memory_limit_in_MB INT,
Core_limit SMALLINT)

INSERT INTO #SQLVersionResourceLimitations
(SQL_Version, SQL_Edition, Memory_limit_in_MB, Core_limit)
VALUES
('2017','Express','1410','4'),
('2017','Standard','131072','24'),
('2017','Enterprise','-1','-1'),
('2016','Express','1410','4'),
('2016','Standard','131072','24'),
('2016','Enterprise','-1','-1'),
('2014','Express','1410','4'),
('2014','Standard','131072','16'),
('2014','Enterprise','-1','-1'),
('2012','Express','1410','4'),
('2012','Standard','65536','16'),
('2012','Enterprise','-1','-1'),
('2008 R2','Express','1410','4'),
('2008 R2','Standard','65536','16'),
('2008 R2','Enterprise','-1','-1'),
('2008','Express','1410','4'),
('2008','Standard','65536','16'),
('2008','Enterprise','-1','-1')

DECLARE @MemoryLimit INT
SELECT @MemoryLimit = Memory_limit_in_MB FROM #SQLVersionResourceLimitations WHERE SQL_Version = @SQLVersion and SQL_Edition = @SQLEdition

DECLARE @CoreLimit SMALLINT
SELECT @CoreLimit = Core_limit FROM #SQLVersionResourceLimitations WHERE SQL_Version = @SQLVersion and SQL_Edition = @SQLEdition

/* Build licensing costs */


	IF @LicenseMethod = 'Core' and @ServerType != 'Host' and @CoreNumber IS NOT NULL
		BEGIN 
		
		INSERT INTO #LicenseCostForCores
		SELECT Server_Type, License_Type, SQL_Version, SQL_Edition, Licenses_Needed, License_Cost, SA_yearly_cost, License_Cost + SA_yearly_cost
		FROM (
			SELECT Server_Type, License_Type, SQL_Version, SQL_Edition, Licenses_Needed, License_Cost,
				CASE WHEN @SoftwareAssurance = 'Y' and @CoreSACost IS NULL THEN License_Cost * @EstimatedCoreSAPercent
				WHEN @SoftwareAssurance = 'Y' and @CoreSACost is NOT NULL THEN @CoreSACost * Licenses_Needed
				WHEN @SoftwareAssurance = 'N' THEN 0
				ELSE 0 END AS SA_yearly_cost
			FROM (
				SELECT Server_Type, License_Type, SQL_Version, SQL_Edition, Licenses_Needed,
					CASE WHEN @CoreLicenseCost IS NULL and @SQLEdition = 'Standard' THEN Licenses_Needed * @MSRPStndCoreLicenseCost
					WHEN @CoreLicenseCost IS NULL and @SQLEdition = 'Enterprise' THEN Licenses_Needed * @MSRPEntCoreLicenseCost 
					WHEN @CoreLicenseCost IS NOT NULL THEN Licenses_Needed * @CoreLicenseCost
					ELSE 0 END as License_Cost
				FROM (
						SELECT @ServerType as Server_Type, @LicenseMethod as License_Type, @SQLVersion as SQL_Version, @SQLEdition as SQL_Edition,
							CASE WHEN @SQLEdition in ('Enterprise','Standard') and @EvenPhysicalCoreNumber < 4 THEN 2 
							WHEN @SQLEdition in ('Enterprise','Standard') THEN @EvenPhysicalCoreNumber / 2 
							ELSE 0 END as Licenses_Needed) A) B) C			

		END
	
IF @LicenseMethod = 'CAL' and @SQLEdition = 'Standard' and @ServerType != 'Host' and @CALnumber IS NOT NULL

	BEGIN 
		
		INSERT INTO #LicenseCostForCALs
				SELECT Server_Type, License_Type, SQL_Version, SQL_Edition, CALS_Needed, CAL_Server_Cost, CAL_Cost, SA_yearly_cost,
				CAL_Server_Cost + CAL_Cost + SA_yearly_cost as Total_year1_cost
				FROM (
					SELECT Server_Type, License_Type, SQL_Version, SQL_Edition, CALS_Needed, CAL_Server_Cost, CAL_Cost, 
					CASE WHEN @CALSACost IS NULL THEN CAL_Cost * @EstimatedCALSAPercent ELSE CAL_Cost * @CALSACost END AS SA_yearly_cost
					FROM (
						SELECT @ServerType as Server_Type, @LicenseMethod as License_Type, @SQLVersion as SQL_Version, @SQLEdition as SQL_Edition, @CALnumber as CALS_Needed, 
						CASE WHEN @CALServerLicenseCost IS NULL THEN @MSRPCALServerLicenseCost ELSE @CALServerLicenseCost END as CAL_Server_Cost, 
						CASE WHEN @CALCost IS NULL THEN @CALnumber * @MSRPCALCost 
							ELSE @CALnumber * @CALCost END as CAL_Cost) A) B

	END

IF @LicenseMethod = 'CAL' and @SQLEdition != 'Standard' and @ServerType != 'Host' and @CALnumber IS NOT NULL
and @CALServerLicenseCost IS NOT NULL and @CALCost IS NOT NULL and @CALCost IS NOT NULL

	BEGIN 
		
		INSERT INTO #LicenseCostForCALs
				SELECT Server_Type, License_Type, SQL_Version, SQL_Edition, CALS_Needed, CAL_Server_Cost, CAL_Cost, SA_yearly_cost,
				CAL_Server_Cost + CAL_Cost + SA_yearly_cost as Total_year1_cost
				FROM (
					SELECT Server_Type, License_Type, SQL_Version, SQL_Edition, CALS_Needed, CAL_Server_Cost, CAL_Cost, 
					CAL_Cost * @CALSACost AS SA_yearly_cost
					FROM (
						SELECT @ServerType as Server_Type, @LicenseMethod as License_Type, @SQLVersion as SQL_Version, @SQLEdition as SQL_Edition, @CALnumber as CALS_Needed, 
						@CALServerLicenseCost as CAL_Server_Cost, 
						@CALnumber * @CALCost as CAL_Cost) A) B

	END

IF @ServerType = 'Host' and @LicenseMethod != 'CAL' and @CoreNumber IS NOT NULL

BEGIN 

		INSERT INTO #LicenseCostForCores
		SELECT Server_Type, License_Type, SQL_Version, SQL_Edition, Licenses_Needed, License_Cost, SA_yearly_cost, License_Cost + SA_yearly_cost
		FROM (
			SELECT Server_Type, License_Type, SQL_Version, SQL_Edition, Licenses_Needed, License_Cost,
				CASE WHEN @SoftwareAssurance = 'Y' and @CoreSACost IS NULL THEN License_Cost * @EstimatedCoreSAPercent
				WHEN @SoftwareAssurance = 'Y' and @CoreSACost IS NOT NULL THEN @CoreSACost * Licenses_Needed
				WHEN @SoftwareAssurance = 'N' THEN 0
				ELSE 0 END AS SA_yearly_cost
			FROM (
				SELECT Server_Type, License_Type, SQL_Version, SQL_Edition, Licenses_Needed,
					CASE WHEN @CoreLicenseCost IS NULL and @SQLEdition = 'Enterprise' THEN Licenses_Needed * @MSRPEntCoreLicenseCost
					WHEN @CoreLicenseCost IS NULL and @SQLEdition = 'Standard' THEN Licenses_Needed * @MSRPStndCoreLicenseCost 
					WHEN @CoreLicenseCost IS NOT NULL THEN Licenses_Needed * @CoreLicenseCost
					ELSE 0 END as License_Cost
				FROM (
						SELECT @ServerType as Server_Type, @LicenseMethod as License_Type, @SQLVersion as SQL_Version, @SQLEdition as SQL_Edition,
							CASE WHEN @EvenPhysicalCoreNumber < 4 THEN 2 
							WHEN @EvenPhysicalCoreNumber >= 4 THEN @EvenPhysicalCoreNumber / 2 
							ELSE 0 END as Licenses_Needed) A) B) C


END 

/* Execute series of checks to see if there are any warnings or informational messages for the user to be mindful of */

-- Critical Messages

IF @SQLVersion in ('2000', '2005') and @Override = 0
	BEGIN 
		INSERT into #LicenseInformation
		SELECT 'Critical', 'SQL ' + @SQLVersion + ' is no longer supported by Microsoft. Consider moving to a newer version.'
		,'https://dustindorsey.com/unsupported'
	END

IF @ServerType != 'Host' and @MemoryLimit < @MaxMemoryMB and @MemoryLimit != -1 and @Override = 0
	BEGIN 
		INSERT into #LicenseInformation
		SELECT 'Critical', 'You have allocated more memory then SQL Server ' + @SQLVersion + ' ' + @SQLEdition +  ' edition will allow. SQL will only use up to ' + CONVERT(NVARCHAR(20),@MemoryLimit) + 'MB of memory'
		,'https://dustindorsey.com/resources'
	END

IF @ServerType != 'Host' and  @CoreLimit < @CoreNumber and @CoreLimit != -1 and @Override = 0
	BEGIN 
		INSERT into #LicenseInformation
		SELECT 'Critical', 'You have allocated more cores then SQL Server ' + @SQLVersion + ' ' + @SQLEdition +  ' edition will allow. SQL will only use up to ' + CONVERT(NVARCHAR(20),@CoreLimit) + ' cores'
		,'https://dustindorsey.com/resources'
	END

-- Warning Messages

IF @CALnumber is not null and @SQLEdition = 'Enterprise' and @Override = 0
	BEGIN 
		INSERT into #LicenseInformation
		SELECT 'Warning', 'Licensing by CALS is only availible on Standard Edition with the new licensing model. Please work with you licensing rep if you have older CAL licenses valid for other versions'
		,'https://dustindorsey.com/cals'
	END

IF @SoftwareAssurance = 'N' and @SQLEdition not in ('Express','Developer') and @Override = 0
	BEGIN 
		INSERT into #LicenseInformation
		SELECT 'Warning', 'It is recommended to include software assurance, however, if you choose not you will need to be sure you understand how this affects the way you use your licenses'
		,'https://dustindorsey.com/software-assurance'
	END

IF @CoreNumber < 4 and @SQLEdition != 'Express' and @Override = 0
	BEGIN 
		INSERT into #LicenseInformation
		SELECT 'Warning', 'You are running less cores then the minimal license count. While you can do this understand that this means you are paying to license cores you are not using'
		,'https://dustindorsey.com/licensing-minimums'
	END

IF ((@LicenseMethod = 'Core' and @CoreNumber IS NOT NULL AND (@CoreLicenseCost IS NULL OR (@CoreSACost is NULL AND @SoftwareAssurance = 'Y'))) OR  (@LicenseMethod = 'CAL' and @CALnumber is not null and (@CALCost is NULL OR @CALServerLicenseCost IS NULL OR (@CALSACost IS NULL AND @SoftwareAssurance = 'Y')))) and @SQLEdition != 'Express' and @Override = 0
	BEGIN 
		INSERT into #LicenseInformation
		SELECT 'Warning', 'You are missing pricing information for your licenses so the MSRP\estimated costs was used. This is a starting point and not neccesarily what you will actually pay'
		,'https://dustindorsey.com/pricing'
	END

IF (@CoreNumber % 2 = 1) and @SQLEdition != 'Express' and @Override = 0
	BEGIN 
		INSERT into #LicenseInformation
		SELECT 'Warning', 'You selected an odd number of cores. Licenses are sold in 2-packs so you will need to buy licenses to cover more cores then you are using'
		,'https://dustindorsey.com/licensing-minimums'
	END

IF @SQLVersion in ('2008', '2008 R2') and @Override = 0
	BEGIN 
		INSERT into #LicenseInformation
		SELECT 'Warning', 'SQL ' + @SQLVersion + ' support will end on July 9, 2019. Consider moving to a newer version'
		,'https://dustindorsey.com/unsupported'
	END

IF @ServerType in ('VM','Container') and @SoftwareAssurance = 'N' and @SQLEdition not in ('Express','Developer') and @Override = 0
	BEGIN 
		INSERT into #LicenseInformation
		SELECT 'Warning','You are licensing a virtual machine\container without software assurance. Be aware this limits your abiliity to move around on different hosts'
		,'https://dustindorsey.com/software-assurance'
	END

IF @MaxMemoryMB <= 4096 and @MaxMemoryMB IS NOT NULL and @SQLEdition != 'Express' and @Override = 0
	BEGIN 
		INSERT into #LicenseInformation
		SELECT 'Warning','Microsoft recommends that you allocate at least 4GB of memory for versions other then Express'
		,'https://dustindorsey.com/licensing-minimums'
	END

IF @MaxMemoryMB <= 1024 and @MaxMemoryMB IS NOT NULL and @SQLEdition = 'Express' and @Override = 0
	BEGIN 
		INSERT into #LicenseInformation
		SELECT 'Warning','Microsoft recommends that you allocate at least 1GB of memory for Express'
		,'https://dustindorsey.com/licensing-minimums'
	END

IF @HighAvailability = 'AG' and  @SQLVersion in ('2012') and @ServerType != 'Host' and @Override = 0
	BEGIN 
		INSERT into #LicenseInformation
		SELECT 'Warning', 'There were significant performance improvements made to Availability Groups in SQL 2014. Consider using a later version if possible'
		,'https://dustindorsey.com/software-assurance'
	END

IF @HighAvailability IS NOT NULL and @ServerType != 'Host' and @SoftwareAssurance = 'N' and @SQLEdition not in ('Express','Developer') and @Override = 0
	BEGIN 
		INSERT into #LicenseInformation
		SELECT 'Warning', 'You have selected high availability, but not software assurance. This may require that you license all servers including passive ones'
		,'https://dustindorsey.com/software-assurance'
	END

IF @HighAvailability = 'Mirroring' and @ServerType != 'Host' and @Override = 0
	BEGIN 
		INSERT into #LicenseInformation
		SELECT 'Warning', 'Mirroring was deprecated in SQL 2012. While you still can use it, it will be removed from future versions. Consider using Availability Groups as a replacement'
		,'https://dustindorsey.com/software-assurance'
	END

IF @SQLEdition = 'Developer' and @SQLVersion in ('2000','2005','2008','2008 R2','2012') and @Override = 0
	BEGIN 
		INSERT into #LicenseInformation
		SELECT 'Informational', 'Check with your licensing rep to see if there is a cost here. Developer edition was made free starting in SQL 2014, but earlier versions could require costs or be covered under MSDN\Visual studio subscriptions'
		,'https://dustindorsey.com/nonprod'
	END

-- Informational messages

IF @SQLEdition = 'Express' and @Override = 0
	BEGIN 
		INSERT into #LicenseInformation
		SELECT 'Informational', 'You are using a free version of SQL'
		,'https://dustindorsey.com/editions'
	END

IF @ServerType = 'Physical' and @CoreNumber < 16 and (@MaxMemoryMB is null or @MaxMemoryMB < 128000) and @Override = 0
	BEGIN 
		INSERT into #LicenseInformation
		SELECT 'Informational', 'You are running on a physical server, but your resource allocation is low. You may want to consider running on a virtual server'
		,'https://dustindorsey.com/editions'
	END

IF @CoreNumber > 40 and @LicenseMethod != 'CAL' and @SQLEdition not in ('Express','Developer') and @Override = 0
	BEGIN 
		INSERT into #LicenseInformation
		SELECT 'Informational', 'That is a lot of cores which is going to be expensive. If you have not do so already you may want to look at tuning opportunities'
		,'https://dustindorsey.com/editions'
	END

IF @CALnumber is not null and @CALnumber > 0 and @Override = 0
	BEGIN 
		INSERT into #LicenseInformation
		SELECT 'Informational', 'You are using CAL licenses. Be sure that you are correctly assigning these and documenting how these are assigned'
		,'https://dustindorsey.com/cals'
	END

IF (@ServerType = 'Host' or @ServerType = 'Physical') and @CoreNumber is not NULL and @Override = 0
	BEGIN 
		INSERT into #LicenseInformation
		SELECT 'Informational', 'You are licensing a physical server by cores. Be sure you are not including hyper-threading and only counting the actual physical cores'
		,'https://dustindorsey.com/hyper-threading'
	END

IF @CoreNumber < 8 and @SQLEdition = 'Enterprise' and @MaxMemoryMB < '64000' and @Override = 0
	BEGIN 
		INSERT into #LicenseInformation
		SELECT 'Informational', 'Resource allocation is low for Enterprise edition. While this may be valid, make sure you understand why you are needing Enterprise edition'
		,'https://dustindorsey.com/editions'
	END

IF @SoftwareAssurance = 'Y' and @SQLEdition not in ('Express','Developer') and @Override = 0
	BEGIN 
		INSERT into #LicenseInformation
		SELECT 'Informational', 'Good call! You selected to include Software Assurance. Be mindful that you will need to pay each year to maintain this'
		,'https://dustindorsey.com/software-assurance'
	END

IF @HighAvailability IS NOT NULL and @ServerType != 'Host' and @SQLEdition not in ('Express','Developer') and @Override = 0
	BEGIN 
		INSERT into #LicenseInformation
		SELECT 'Informational', 'Depending on how you you are using high availability depends on how much you need to license. Check out this article to be sure'
		,'https://dustindorsey.com/software-assurance'
	END

IF @HighAvailability IS NOT NULL and @ServerType != 'Host' and @SQLEdition = 'Standard' and @Override = 0
	BEGIN 
		INSERT into #LicenseInformation
		SELECT 'Informational', 'You are using Availability groups on Standard edition, be sure you understand the limitations'
		,'https://dustindorsey.com/software-assurance'
	END

IF @SQLEdition = 'Developer' and @SQLVersion in ('2014','2016','2017','2019') and @Override = 0
	BEGIN 
		INSERT into #LicenseInformation
		SELECT 'Informational', 'Developer edition was made free starting in SQL 2014'
		,'https://dustindorsey.com/nonprod'
	END

IF @ServerType = 'Host' and @Override = 0
	BEGIN 
		INSERT into #LicenseInformation
		SELECT 'Informational', 'Be sure that you include all physical cores from all hosts'
		,'https://dustindorsey.com/licensing'
	END

/* Display results */

IF EXISTS (SELECT 1 FROM #LicenseCostForCores)
SELECT * FROM #LicenseCostForCores

IF EXISTS (SELECT 1 FROM #LicenseCostForCALs)
SELECT * FROM #LicenseCostForCALs

IF EXISTS (SELECT 1 FROM #LicenseInformation)
SELECT * FROM #LicenseInformation
WHERE @Override = 0

SET NOCOUNT OFF
GO


