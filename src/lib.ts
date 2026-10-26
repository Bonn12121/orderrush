import {createClient} from '@supabase/supabase-js';
export const configured=Boolean(import.meta.env.VITE_SUPABASE_URL&&import.meta.env.VITE_SUPABASE_PUBLISHABLE_KEY);
export const supabase=configured?createClient(import.meta.env.VITE_SUPABASE_URL,import.meta.env.VITE_SUPABASE_PUBLISHABLE_KEY):null;
export type Item={id:string;label:string;content:string};
export type Challenge={id:string;title:string;description:string;status:string;challenge_items:Item[]};
export type Result={is_correct:boolean;score:number;completion_ms:number;rank:number;participants:number;correct_percent:number;correct_order:Item[]};
export type Rank={player_id:string;display_name:string;score:number;completion_ms:number|null;submitted_at:string|null;status:string;rank:number};
export function shuffle<T>(xs:T[]):T[]{const a=[...xs];for(let i=a.length-1;i>0;i--){const j=Math.floor(Math.random()*(i+1));[a[i],a[j]]=[a[j],a[i]]}return a}
export function time(ms:number|null){return ms===null?'—':`${(ms/1000).toFixed(1)}s`}
