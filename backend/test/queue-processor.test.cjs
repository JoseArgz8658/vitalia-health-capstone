const {createQueueProcessor,acquireProcessorLock,releaseProcessorLock,recoverInterruptedProcessing,UnconfirmedProcessingError}=require('../dist/processing/queue');
const id='33333333-3333-4333-8333-333333333333';
test('bloqueo exclusivo y recuperación solo de trabajos en proceso',async()=>{
 const query=jest.fn(async sql=>sql.includes('try_advisory')?{rows:[{locked:true}]}:{rows:[{id}]});
 expect(await acquireProcessorLock({query})).toBe(true);expect(await recoverInterruptedProcessing({query})).toBe(1);await releaseProcessorLock({query});
 expect(query.mock.calls[1][0]).toContain("WHERE status='processing'");expect(query.mock.calls[1][0]).toContain("failure_code='processing_interrupted'");
});
test('sin modelos disponibles no reclama ni modifica trabajos',async()=>{
 const db={query:jest.fn()},process=jest.fn();expect(await createQueueProcessor(db,process,async()=>[])()).toEqual({state:'model_unavailable'});expect(db.query).not.toHaveBeenCalled();expect(process).not.toHaveBeenCalled();
});
test('consume un trabajo compatible almacenado y nunca vuelve a solicitar aprobación',async()=>{
 const db={query:jest.fn(async()=>({rows:[{id}]}))},process=jest.fn(async()=>({outcome:'requires_review',processingId:id,approved:false}));
 const result=await createQueueProcessor(db,process,async()=>['qwen3:4b-instruct'])();expect(result.state).toBe('processed');expect(result.result.approved).toBe(false);expect(process).toHaveBeenCalledWith(id);
 const [sql,args]=db.query.mock.calls[0];expect(sql).toContain("p.status='queued'");expect(sql).toContain("d.status='stored'");expect(sql).toContain('p.model=ANY($1::text[])');expect(args).toEqual([['qwen3:4b-instruct']]);
});
test('cola vacía no ejecuta procesador y un estado no confirmado detiene el ciclo',async()=>{
 const process=jest.fn();expect((await createQueueProcessor({query:async()=>({rows:[]})},process,async()=>['local'])()).state).toBe('idle');expect(process).not.toHaveBeenCalled();
 await expect(createQueueProcessor({query:async()=>({rows:[{id}]})},async()=>({outcome:'processing_error',processingId:id,failureRecorded:false}),async()=>['local'])()).rejects.toBeInstanceOf(UnconfirmedProcessingError);
});
