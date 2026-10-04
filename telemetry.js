(() => {
  const post = value => window.webkit.messageHandlers.splashMetrics.postMessage(value);
  window.splashTrack = (response, fetcher, token, effort, requestStart) => {
    const started = requestStart; let first = 0, text = '', buffer = '', ended = false, pending = false;
    let count = 0, firstCount = 0, lastSample = 0, latestSpeed = 0, reasoning = null, finalStats = false;
    const decoder = new TextDecoder();
    function publish(phase, actual = false, speed = latestSpeed, ttft = first ? (first-started)/1000 : null) {
      post({phase, actual, speed, tokens:count, ttft, elapsed:(performance.now()-started)/1000, effort, reasoning});
    }
    async function sample() {
      if (ended || pending || !text) return;
      pending = true;
      try {
        const r = await fetcher('/tokenize', {method:'POST',headers:{'Content-Type':'application/json','Authorization':'Bearer '+token}, body:JSON.stringify({content:text,add_special:false})});
        const o = await r.json();
        if (!ended && Array.isArray(o.tokens)) {
          count = o.tokens.length;
          if (!lastSample) firstCount = count;
          latestSpeed = lastSample ? Math.max(0,(count-firstCount)/Math.max(.001,(performance.now()-lastSample)/1000)) : 0;
          firstCount = count; lastSample = performance.now(); publish('generating');
        }
      } catch {} finally { pending = false; }
    }
    const timer = setInterval(() => { if (!ended) { if (!first) publish('waiting'); else { publish('generating'); sample(); } } }, 1000);
    publish('waiting');
    function processEvent(event) {
      const data = event.split('\n').filter(l=>l.startsWith('data:')).map(l=>l.slice(5).trim()).join('\n');
      if (!data) return;
      if (data === '[DONE]') { ended = true; clearInterval(timer); if (!finalStats) publish('done'); return; }
      const chunk = JSON.parse(data);
      if (chunk.error) { ended=true; clearInterval(timer); publish('error'); return; }
      const delta = chunk.choices?.[0]?.delta;
      if (delta?.content || delta?.reasoning_content) {
        if (!first) first = performance.now();
        text += (delta.reasoning_content || '') + (delta.content || '');
      }
      if (chunk.usage) {
        count = chunk.usage.completion_tokens ?? count;
        reasoning = chunk.usage.completion_tokens_details?.reasoning_tokens ?? null;
        const latency = chunk.metrics?.request_latency ?? {};
        latestSpeed = latency.stream_tokens_per_second ?? 0;
        finalStats = true; ended = true; clearInterval(timer);
        publish('done',true,latestSpeed,Number.isFinite(latency.start_to_first_token_ms) ? latency.start_to_first_token_ms/1000 : undefined);
      }
    }
    const reader = response.body.getReader();
    const stream = new ReadableStream({
      async pull(controller) {
        try {
          const {value,done} = await reader.read();
          if (done) {
            buffer += decoder.decode(); if(buffer.trim()) processEvent(buffer);
            clearInterval(timer); if(!ended) { ended=true; publish('interrupted'); }
            controller.close(); return;
          }
          buffer += decoder.decode(value,{stream:true}); const events=buffer.split(/\r?\n\r?\n/); buffer=events.pop();
          events.forEach(processEvent); controller.enqueue(value);
        } catch(e) { ended=true; clearInterval(timer); publish(e.name==='AbortError'?'cancelled':'error'); controller.error(e); }
      },
      cancel(reason) { ended=true;clearInterval(timer);publish('cancelled');return reader.cancel(reason); }
    });
    return new Response(stream,{status:response.status,statusText:response.statusText,headers:response.headers});
  };
})();
