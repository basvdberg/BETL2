﻿
CREATE procedure [dbo].[detect_dead_batches]
	@batch_id int 

as 
begin
	declare 
		@proc_name as sysname =  object_name(@@PROCID)
		,@batch_dead_time_min as int -- after this period of inactivity the batch will be seen as stopped.. 
		,@min_batch_start_dt as datetime -- performance filter to filter batches that started more than @batch_dead_time_min ago.
		,@i as int =0

	-- standard BETL header code... 
	set nocount on 
	exec dbo.log_batch @batch_id, 'Header', '?(b?)', @proc_name , @batch_id
	-- END standard BETL header code... 

	-- first detect dead batches (running too long idle) 
	exec dbo.getp @prop='batch_dead_time_min', @value=@batch_dead_time_min output, @batch_id = @batch_id 
	set @min_batch_start_dt = dateadd(minute, -@batch_dead_time_min, getdate()) 
	exec dbo.log_batch @batch_id, 'VAR', '@min_batch_start_dt ?', @min_batch_start_dt

	update b
	set status_id = 700 
	from dbo.batch b
	left join 
	( select b.batch_id, max(tl.log_dt) log_dt 
	  from dbo.Logging tl 
	  inner join dbo.Transfer t on tl.transfer_id = t.transfer_id 
	  inner join dbo.Batch b on t.batch_id = b.batch_id
		where b.status_id = 400 -- running
		and b.batch_start_dt < @min_batch_start_dt 
		
	  group by b.batch_id ) 
	latest_log_dt on latest_log_dt.batch_id = b.batch_id and latest_log_dt.log_dt > @min_batch_start_dt -- performance filter
	--inner join static.Status s on b.status_id = s.status_id 
	where b.status_id = 400 -- running
	and ( b.batch_start_dt < @min_batch_start_dt -- performance filter
			or b.guid is null) -- for null guids we always kill the batch because these batches are started from ssms for debugging purpose
--	and b.batch_name = @batch_name 
	and ( latest_log_dt.batch_id is null -- there is no activity logged after @min_batch_start_dt
			or b.guid is null) -- for null guids we always kill the batch because these batches are started from ssms for debugging purpose

	set @i= @@ROWCOUNT
	if @i>0 
	begin
		exec dbo.log_batch @batch_id, 'INFO', 'stopped ? dead batches .', @i
	
		-- also stop transfers for stopped batches
		update t
		set status_id = 700 
		from dbo.Transfer t
		inner join dbo.Batch b on t.batch_id = b.batch_id 
		where b.status_id = 700 and t.status_id in ( 600, 400) 
		
		set @i= @@ROWCOUNT
		exec dbo.log_batch @batch_id, 'INFO', 'stopped ? dead transfers .', @i
	end

	-- standard BETL footer code... 
	exec dbo.log_batch @batch_id, 'Footer', '?(b?)', @proc_name , @batch_id
	-- END standard BETL header code... 
end