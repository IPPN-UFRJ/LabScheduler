import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';
const cors = {'Access-Control-Allow-Origin':'*','Access-Control-Allow-Headers':'authorization, x-client-info, apikey, content-type','Access-Control-Allow-Methods':'POST, OPTIONS'};
const response=(data:unknown,status=200)=>new Response(JSON.stringify(data),{status,headers:{...cors,'Content-Type':'application/json'}});
Deno.serve(async req=>{
 if(req.method==='OPTIONS')return new Response('ok',{headers:cors});
 if(req.method!=='POST')return response({error:'Method not allowed'},405);
 try{
  const auth=req.headers.get('Authorization');if(!auth?.startsWith('Bearer '))return response({error:'Unauthorized'},401);
  const url=Deno.env.get('SUPABASE_URL')!;const anon=Deno.env.get('SUPABASE_ANON_KEY')!;const service=Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;
  const caller=createClient(url,anon,{global:{headers:{Authorization:auth}}});
  const {data:{user},error:ue}=await caller.auth.getUser();if(ue||!user)return response({error:'Unauthorized'},401);
  const body=await req.json();const {action,institution_id}=body;
  if(typeof institution_id!=='string')return response({error:'Missing institution'},400);
  const admin=createClient(url,service);
  const {data:member,error:me}=await admin.from('memberships').select('role').eq('institution_id',institution_id).eq('user_id',user.id).maybeSingle();
  if(me||member?.role!=='admin')return response({error:'Administrator permission required'},403);
  if(action==='create'){
   const email=String(body.email||'').trim().toLowerCase();const password=String(body.password||'');
   if(!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email)||password.length<12)return response({error:'Valid email and password with 12+ characters required'},400);
   const {data:created,error:ce}=await admin.auth.admin.createUser({email,password,email_confirm:true});if(ce||!created.user)return response({error:ce?.message||'Could not create user'},400);
   const id=created.user.id;
   const {error:membershipError}=await admin.from('memberships').insert({institution_id,user_id:id,role:'researcher'});
   if(membershipError){await admin.auth.admin.deleteUser(id);return response({error:membershipError.message},400)}
   if(body.equipment_id){const {data:eq}=await admin.from('equipment').select('institution_id').eq('id',body.equipment_id).maybeSingle();if(eq?.institution_id===institution_id)await admin.from('equipment_authorizations').insert({equipment_id:body.equipment_id,user_id:id,granted_by:user.id})}
   return response({user_id:id});
  }
  if(action==='list'){
   const {data:members,error:err}=await admin.from('memberships').select('user_id').eq('institution_id',institution_id);if(err)return response({error:err.message},400);
   const users=[];for(const m of members||[]){const {data}=await admin.auth.admin.getUserById(m.user_id);if(data.user)users.push({user_id:m.user_id,email:data.user.email||'',active:!data.user.banned_until})}
   return response({users});
  }
  const target=String(body.target_user_id||'');
  const {data:targetMember}=await admin.from('memberships').select('role').eq('user_id',target).eq('institution_id',institution_id).maybeSingle();
  if(!targetMember)return response({error:'User outside institution'},403);
  if(action==='set_active'){
   if(target===user.id||targetMember.role==='admin')return response({error:'Cannot change administrator account'},403);
   const {error}=await admin.auth.admin.updateUserById(target,{ban_duration:body.active?'none':'876000h'});return response(error?{error:error.message}:{ok:true},error?400:200);
  }
  if(action==='grant_equipment'){
   const equipmentId=String(body.equipment_id||'');const {data:eq}=await admin.from('equipment').select('institution_id').eq('id',equipmentId).maybeSingle();if(eq?.institution_id!==institution_id)return response({error:'Equipment outside institution'},403);
   const {error}=await admin.from('equipment_authorizations').upsert({equipment_id:equipmentId,user_id:target,granted_by:user.id});return response(error?{error:error.message}:{ok:true},error?400:200);
  }
  return response({error:'Unknown action'},400);
 }catch(e){return response({error:e instanceof Error?e.message:'Unexpected error'},500)}
});
