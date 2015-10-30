-- Script to purge data older than 30 days 
declare @purgeDate datetime = dateadd(dd,-30,getdate())

select @purgeDate = convert(datetime , DateAdd(Day, Datediff(Day,0, @purgeDate), 0))
select @purgeDate

declare @messagesToPurge table
(messageId nvarchar(max) , 
	MessageContextId int , 
	MessageInstructionId int , 
	ESignMessageContextId int  , 
	MessageSettingId int
)
insert into @messagesToPurge(messageId , MessageContextId , MessageInstructionId , ESignMessageContextId , MessageSettingId)
select messageid  , 
		MessageContext_MessageContextId , 
		MessageInstruction_MessageInstructionId , 
		EsignMessageContext_EsignMessageContextId , 
		MessageSetting_MessageSettingId
from messages where date < @purgeDate

-- MessageApplicationSettings
delete MAS 
from MessageApplicationSettings MAS inner join @messagesToPurge M on 
MAs.MessageId = M.messageId

-- Message Context
delete MC
from MessageContexts MC inner join @messagesToPurge M on 
MC.MessageContextId = M.MessageContextId

-- Message Instruction
delete MI 
from MessageInstructions MI inner join @messagesToPurge M on 
MI.MessageInstructionId = M.MessageInstructionId

-- ESignMessageContext
delete EMC
from EsignMessageContexts EMC inner join @messagesToPurge M on 
EMC.EsignMessageContextId = M.ESignMessageContextId

-- MessageUsages
delete MU 
from MessageUsages MU where MU.CreatedDate < @purgeDate

-- MessageSettings
delete MS
from MessageSettings MS inner join @messagesToPurge M on 
MS.MessageSettingId = M.MessageSettingId


---- Destinations Related Data
declare @destinationsToPurge table
(
DestinationId int , 
DestinationContextId int ,
ESignDestinationContextId int , 
SmtpLogId int , 
SmtpHistoryId int
)

insert into @destinationsToPurge(DestinationId , DestinationContextId , ESignDestinationContextId,SmtpHistoryId , SmtpLogId)
select D.DestinationId , D.DestinationContext_DestinationContextId , D.EsignDestinationContext_EsignDestinationContextId , 
SmtpHistory_SmtpHistoryId , SmtpLog_SmtpLogId
from Destinations D inner join @messagesToPurge M on 
M.messageId = D.Message_MessageId

-- destination context 
delete DC
from DestinationContexts DC inner join @destinationsToPurge D on 
D.DestinationContextId = DC.DestinationContextId

-- esign destination context
delete EDC
from EsignDestinationContexts EDC inner join @destinationsToPurge D on 
D.ESignDestinationContextId = EDC.EsignDestinationContextId

-- smtp log 
delete SL 
from SmtpLogs SL inner join @destinationsToPurge D on 
D.SmtpLogId = SL.SmtpLogId

-- smtp history 
delete SH
from SmtpHistories SH inner join @destinationsToPurge D on 
D.SmtpHistoryId = SH.SmtpHistoryId

-- large mail
delete LD 
from LargeAttachmentDetail LD inner join LargeAttachmentHeader LH on 
LH.HeaderId = LD.LargeAttachmentHeader_HeaderId
inner join @destinationsToPurge D on 
LH.DestinationId = D.DestinationId

delete LH
from LargeAttachmentHeader LH 
inner join @destinationsToPurge D on 
LH.DestinationId = D.DestinationId

-- delete destinations
delete D
from Destinations D inner join @destinationsToPurge DP on 
D.DestinationId = DP.DestinationId

-- delete messages
delete M
from Messages M inner join @messagesToPurge MP on 
MP.messageId = M.MessageId







