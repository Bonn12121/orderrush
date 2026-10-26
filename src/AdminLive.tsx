import {useCallback,useEffect,useMemo,useState} from 'react';
import {Play,RotateCcw,Trophy,Users} from 'lucide-react';
import {supabase,time,type Rank} from './lib';

type LivePlayer={player_id:string;display_name:string;started_at:string;status:'playing'|'submitted';score:number;completion_ms:number|null;is_correct:boolean|null};

export default function AdminLive({challengeId,onReplay,onlineIds,eventTick}:{challengeId:string;onReplay:()=>Promise<void>;onlineIds:string[];eventTick:number}){
 const [players,setPlayers]=useState<LivePlayer[]>([]);
 const [ranks,setRanks]=useState<Rank[]>([]);
 const [now,setNow]=useState(Date.now());
 const [working,setWorking]=useState(false);
 const [error,setError]=useState('');
 const reload=useCallback(async()=>{
  if(!supabase)return;
  const [live,board]=await Promise.all([
   supabase.rpc('admin_live_players',{p_challenge:challengeId}),
   supabase.rpc('live_leaderboard',{p_challenge:challengeId})
  ]);
  if(live.error){setError(live.error.message);return}
  if(board.error){setError(board.error.message);return}
  setPlayers((live.data||[]) as LivePlayer[]);
  setRanks((board.data||[]) as Rank[]);
 },[challengeId]);
 useEffect(()=>{const clock=setInterval(()=>setNow(Date.now()),1000);return()=>clearInterval(clock)},[]);
 useEffect(()=>{reload()},[reload,eventTick]);
 const playing=useMemo(()=>players.filter(p=>p.status==='playing'&&onlineIds.includes(p.player_id)),[players,onlineIds]);
 async function reset(){
  if(!supabase||working||!window.confirm('Xóa toàn bộ điểm và lượt chơi của thử thách này?'))return;
  setWorking(true);setError('');
  const {error:e}=await supabase.rpc('reset_challenge',{p_challenge:challengeId});
  if(e)setError(e.message);else await reload();
  setWorking(false);
 }
 async function replay(){setWorking(true);setError('');try{await onReplay()}catch(e){setError((e as Error).message)}finally{setWorking(false)}}
 return <section className="admin-live">
  <div className="admin-live-heading"><div><span className="eyebrow">DỮ LIỆU TRỰC TIẾP</span><h2>Phòng học đang chơi</h2><p>Thời gian tính từ lúc mỗi người bắt đầu thử thách.</p></div><div className="admin-live-actions"><button className="ghost" onClick={replay} disabled={working}><Play size={17}/> Chơi lại với tài khoản admin</button><button className="danger-button" onClick={reset} disabled={working}><RotateCcw size={17}/> Đặt lại bảng xếp hạng</button></div></div>
  <div className="admin-metrics"><div><Users size={21}/><strong>{playing.length}</strong><span>đang chơi trực tuyến</span></div><div><Trophy size={21}/><strong>{players.filter(p=>p.status==='submitted').length}</strong><span>đã nộp bài</span></div><div><RotateCcw size={21}/><strong>{players.length}</strong><span>tổng người tham gia</span></div></div>
  <div className="admin-live-grid"><div className="admin-live-panel"><h3>Người chơi</h3>{players.length===0?<p className="admin-empty">Chưa có ai vào thử thách.</p>:<div className="admin-player-list">{players.map(p=>{const online=onlineIds.includes(p.player_id);const elapsed=p.status==='playing'?Math.max(0,now-new Date(p.started_at).getTime()):p.completion_ms;return <div className="admin-player" key={p.player_id}><span className={`player-dot ${online?'online':''}`}/><div className="admin-player-name"><strong>{p.display_name}</strong><small>{p.status==='submitted'?'Đã nộp bài':online?'Đang chơi':'Đã rời trang'}</small></div><span className="admin-elapsed">{time(elapsed)}</span><b>{p.status==='submitted'?`${p.score}đ`:'—'}</b></div>})}</div>}</div><div className="admin-live-panel"><h3>Bảng xếp hạng</h3>{ranks.length===0?<p className="admin-empty">Chưa có điểm số.</p>:<div className="admin-player-list">{ranks.slice(0,10).map(r=><div className="admin-player" key={r.player_id}><span className="admin-rank">#{r.rank}</span><div className="admin-player-name"><strong>{r.display_name}</strong><small>{r.status==='submitted'?'Đã nộp bài':'Đang chơi'}</small></div><span className="admin-elapsed">{time(r.completion_ms)}</span><b>{r.score}đ</b></div>)}</div>}</div></div>
  {error&&<p className="admin-error" role="alert">{error}</p>}
 </section>
}
