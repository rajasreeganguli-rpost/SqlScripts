--Script For adding records to configuration parameters

Declare @applicationname1 varchar(20)
Declare @applicationname2 varchar(20)
Declare @versionnumber varchar(20)
declare @paramName varchar(50)
declare @paramValue varchar(50)

-- Change these variables for new headers and database accordingly
set @versionnumber = '2.0.0'

--declare the parameters to insert
declare @paramNames varchar(1000) = 'LargeFileDownloadExpiration,LargeFileDownloadReminder,FileSizeLimitTrialUser,FileSizeLimitPayingUser,LargeFileDownloadUrl,XRpostLargeMailHdr'
declare @paramValues varchar(1000) = '14,7,100,102400,http://largemail.usw.rpost.net/files/{key},X-RPOST-LargeMail'


set @applicationname1 = 'RmailCoreTrans21'	
set @applicationname2 = 'RmailCoreTrans22'	


Declare @pos int, @posV int , @delim char = ','


declare @loop int = 1
While @loop = 1
Begin
	select @pos = CHARINDEX(@delim, @paramNames);
	select @posV = CHARINDEX(@delim, @paramValues);
	If @pos > 0 
		Begin
			set @paramName = ltrim(rtrim(left(@paramNames, @pos - 1)))
			set @paramValue = ltrim(rtrim(left(@paramValues, @posV - 1)))
			print @paramName
		End
	else
		Begin
			set @loop = 0 
			set @paramName = @paramNames
			set @paramValue = @paramValues
			print @paramName
		End

	if not exists (select 1 from ConfigurationParameters where 
			lower(ApplicationName) = lower(@applicationname1) and ReleaseVersion = @versionnumber 
			and lower(name)  =  lower(@paramName) )
	Begin
		insert into ConfigurationParameters (ApplicationName , ReleaseVersion , Name , Value)
		values 
		( @applicationName1 , @versionNumber , @paramName , @paramValue )
	End 

	if not exists (select 1 from ConfigurationParameters where 
			lower(ApplicationName) = lower(@applicationname2) and ReleaseVersion = @versionnumber 
			and lower(name)  =  lower(@paramName) )
	Begin
		insert into ConfigurationParameters (ApplicationName , ReleaseVersion , Name , Value)
		values 
		( @applicationName2 , @versionNumber , @paramName , @paramValue )
	End 
	if @pos > 0 
		Begin
			set @paramNames = RIGHT(@paramNames, len(@paramNames) - @pos);
			SET @pos = CHARINDEX(@delim, @paramNames);
			set @paramValues = RIGHT(@paramValues, len(@paramValues) - @posV);
			SET @posV = CHARINDEX(@delim, @paramValues);
		End

end 


