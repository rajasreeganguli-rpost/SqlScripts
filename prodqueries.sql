--prod queries


			select count(*) from MessageUsages with (nolock)
			where CreatedDate  BETWEEN DATEADD(month, DATEDIFF(month, -1, getdate()) - 2, 0) 
			AND DATEADD(ss, -1, DATEADD(month, DATEDIFF(month, 0, getdate()), 0))

			

			select count(*) from Messages with (nolock)
			where Date  BETWEEN DATEADD(month, DATEDIFF(month, -1, getdate()) - 2, 0) 
			AND DATEADD(ss, -1, DATEADD(month, DATEDIFF(month, 0, getdate()), 0))


-- Usage
select U.Address UserEmailAddress, U.Name as UserName ,isnull(C.Name,'') Customer , isnull(A.UnitsSent,0) TotalUnits
FROM Customers C WITH (NOLOCK)
	inner join  Users U WITH (NOLOCK) ON 
		C.CustomerId = U.Customer_CustomerId 
	left outer join 
		(
			Select M.SenderAddress , Sum(UnitsSent) UnitsSent
				from RPost.dbo.Messages M WITH (NOLOCK) 
					inner JOIN RPost.dbo.MessageUsages MU WITH (NOLOCK) 
				ON M.MessageId = MU.MessageId and
				MU.CreatedDate BETWEEN DATEADD(month, DATEDIFF(month, -1, getdate()) - 2, 0) 
				AND DATEADD(ss, -1, DATEADD(month, DATEDIFF(month, 0, getdate()), 0))
				And MU.IsRejected = 0 
				group by M.SenderAddress
		) A
	on lower(A.SenderAddress) = lower(U.Address)
	order by U.Address