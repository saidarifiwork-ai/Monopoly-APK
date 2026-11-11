const {test}=require('node:test'),assert=require('node:assert/strict');
const {createAuth}=require('../auth');
const {progress,result}=require('../solo-progression');
test('an account starts at Beginner and only consecutive completed levels count',()=>{
 assert.deepEqual(progress().unlockedLevels,['beginner']);
 assert.deepEqual(progress({soloVictories:{ultimate:{wonAt:1,gameId:'fake'}}}).unlockedLevels,['beginner']);
 const account={soloVictories:{beginner:{wonAt:1,gameId:'a'},normal:{wonAt:2,gameId:'b'}}};
 assert.deepEqual(progress(account).completedLevels,['beginner']);assert.deepEqual(progress(account).unlockedLevels,['beginner','easy']);
});
test('a failed progress write does not grant access and replaying a recorded win never grants the next tier',async()=>{
 let fail=true,writes=0;const data={accounts:{said:{id:'said',name:'Said',picture:'',createdAt:1}},sessions:{version:1,sessions:[]}};
 const store={auth:data,save:async(_,value)=>{if(fail)throw Error('offline');writes++;Object.assign(data,JSON.parse(JSON.stringify(value)));}};
 const auth=createAuth({clientId:'test.apps.googleusercontent.com',persistence:store});
 const win={accountId:'said',level:'beginner',gameId:'ABCDEF:0'};
 await assert.rejects(auth.recordSoloWins([win]));assert.deepEqual(auth.soloProgress('said').unlockedLevels,['beginner']);
 fail=false;await auth.recordSoloWins([win]);await auth.recordSoloWins([win]);
 assert.equal(writes,1);assert.deepEqual(auth.soloProgress('said').unlockedLevels,['beginner','easy']);
 await auth.recordSoloWins([{...win,level:'ultimate'}]);assert.deepEqual(auth.soloProgress('said').completedLevels,['beginner']);
});
test('only a complete official solo win against the original opponents qualifies',()=>{
 const room={code:'ABCDEF',phase:'finished',turn:0,players:[{id:'human',accountId:'said',out:false},{id:'bot',bot:true,botLevel:'beginner',out:true}],soloChallenge:{version:1,accountId:'said',level:'beginner',opponentIds:['bot']}};
 assert.equal(result(room).level,'beginner');
 for(const modify of [r=>r.players[1].out=false,r=>r.players[1].temporaryBot=true,r=>r.players[1].botLevel='easy',r=>r.soloChallenge.opponentIds=['other'],r=>r.players[0].out=true,r=>r.turn=1,r=>delete r.soloChallenge,r=>r.phase='playing']){
  const copy=JSON.parse(JSON.stringify(room));modify(copy);assert.equal(result(copy),null);
 }
});
