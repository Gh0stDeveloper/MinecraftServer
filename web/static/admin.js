const tokenInput=document.getElementById('adminToken');
const checkToken=document.getElementById('checkToken');
const authState=document.getElementById('authState');
const worldFile=document.getElementById('worldFile');
const fileTitle=document.getElementById('fileTitle');
const fileMeta=document.getElementById('fileMeta');
const uploadWorld=document.getElementById('uploadWorld');
const uploadLimit=document.getElementById('uploadLimit');
const progressWrap=document.getElementById('progressWrap');
const progressBar=document.getElementById('progressBar');
const progressText=document.getElementById('progressText');
const progressPercent=document.getElementById('progressPercent');
const importLog=document.getElementById('importLog');
let maxUploadMb=4096;
let authenticated=false;

function token(){return tokenInput.value.trim();}
function headers(){return {'X-Admin-Token':token()};}
function human(bytes){const units=['B','KB','MB','GB'];let n=bytes,i=0;while(n>=1024&&i<units.length-1){n/=1024;i++;}return `${n.toFixed(i?1:0)} ${units[i]}`;}
function setAuth(ok,text){authenticated=ok;authState.textContent=text;authState.className=`admin-state ${ok?'ok':'bad'}`;uploadWorld.disabled=!(ok&&worldFile.files.length);}
function setProgress(percent,text){progressWrap.hidden=false;const p=Math.max(0,Math.min(100,percent));progressBar.style.width=`${p}%`;progressPercent.textContent=`${Math.round(p)}%`;progressText.textContent=text;}
function log(text,isError=false){importLog.hidden=false;importLog.textContent=text||'';importLog.classList.toggle('error',isError);}
function failureDetail(data){
  const detail=(data&&typeof data.message==='string'&&data.message.trim())||(data&&typeof data.error==='string'&&data.error.trim())||'El importador no devolvió detalles del fallo.';
  return detail;
}

async function validateToken(){
  if(!token()){setAuth(false,'Introduce el token administrativo.');return false;}
  checkToken.disabled=true;
  try{
    const r=await fetch('/api/admin/check',{headers:headers(),cache:'no-store'});
    const data=await r.json();
    if(!r.ok)throw new Error(data.error||'Token inválido.');
    maxUploadMb=data.max_upload_mb||4096;
    uploadLimit.textContent=`Selecciona .zip o .mcworld. Límite configurado: ${maxUploadMb} MB. La importación crea un backup antes de reemplazar Survival.`;
    sessionStorage.setItem('mcserver-admin-token',token());
    setAuth(true,'Autenticación correcta.');
    return true;
  }catch(e){setAuth(false,e.message);sessionStorage.removeItem('mcserver-admin-token');return false;}
  finally{checkToken.disabled=false;}
}

checkToken.addEventListener('click',validateToken);
tokenInput.addEventListener('input',()=>{authenticated=false;uploadWorld.disabled=true;authState.textContent='Token sin validar.';authState.className='admin-state';});

worldFile.addEventListener('change',()=>{
  const file=worldFile.files[0];
  if(!file){fileTitle.textContent='Seleccionar .zip o .mcworld';fileMeta.textContent='Toca aquí para buscar el mundo en tu teléfono.';uploadWorld.disabled=true;return;}
  fileTitle.textContent=file.name;
  fileMeta.textContent=`${human(file.size)} · listo para subir`;
  const ext=file.name.toLowerCase();
  const valid=ext.endsWith('.zip')||ext.endsWith('.mcworld');
  if(!valid){fileMeta.textContent='Formato no admitido. Usa .zip o .mcworld.';uploadWorld.disabled=true;return;}
  if(file.size>maxUploadMb*1024*1024){fileMeta.textContent=`El archivo supera el límite de ${maxUploadMb} MB.`;uploadWorld.disabled=true;return;}
  uploadWorld.disabled=!authenticated;
});

function upload(file){
  return new Promise((resolve,reject)=>{
    const xhr=new XMLHttpRequest();
    xhr.open('POST','/api/admin/survival/upload');
    xhr.setRequestHeader('X-Admin-Token',token());
    xhr.setRequestHeader('X-Filename',file.name);
    xhr.setRequestHeader('Content-Type','application/octet-stream');
    xhr.upload.onprogress=e=>{if(e.lengthComputable)setProgress((e.loaded/e.total)*92,`Subiendo ${human(e.loaded)} de ${human(e.total)}…`);};
    xhr.onerror=()=>reject(new Error('Se perdió la conexión durante la subida.'));
    xhr.onload=()=>{
      let data={};try{data=JSON.parse(xhr.responseText||'{}');}catch{}
      if(xhr.status<200||xhr.status>=300)return reject(new Error(data.error||`Error HTTP ${xhr.status}`));
      resolve(data);
    };
    xhr.send(file);
  });
}

async function pollImport(id){
  for(let i=0;i<900;i++){
    const r=await fetch(`/api/admin/survival/import-status?id=${encodeURIComponent(id)}`,{headers:headers(),cache:'no-store'});
    const data=await r.json();
    if(!r.ok)throw new Error(data.error||'No se pudo consultar la importación.');
    if(data.state==='queued'){setProgress(94,'Archivo recibido. Esperando al importador…');}
    else if(data.state==='importing'){setProgress(97,'Validando, respaldando e importando Survival…');}
    else if(data.state==='success'){setProgress(100,'Importación completada.');log(data.message||'Survival importado correctamente.');return data;}
    else if(data.state==='failed'){
      const detail=failureDetail(data);
      setProgress(100,'La importación falló. Revisa el detalle de abajo.');
      log(detail,true);
      const error=new Error(detail);
      error.importDetail=true;
      throw error;
    }
    await new Promise(r=>setTimeout(r,2000));
  }
  throw new Error('La importación sigue en proceso; revisa el estado más tarde.');
}

uploadWorld.addEventListener('click',async()=>{
  const file=worldFile.files[0];if(!file)return;
  if(!authenticated&&!(await validateToken()))return;
  uploadWorld.disabled=true;checkToken.disabled=true;log('');importLog.hidden=true;
  try{
    setProgress(1,'Iniciando subida…');
    const queued=await upload(file);
    setProgress(94,'Subida terminada. Preparando importación…');
    await pollImport(queued.id);
    fileMeta.textContent='Importación finalizada correctamente.';
  }catch(e){
    if(!e.importDetail)log(e.message||'La importación no se completó.',true);
    progressText.textContent=e.importDetail?'La importación falló. Revisa el detalle de abajo.':(e.message||'La importación no se completó.');
    fileMeta.textContent='La importación no se completó. El detalle técnico aparece debajo.';
  }
  finally{checkToken.disabled=false;uploadWorld.disabled=!(authenticated&&worldFile.files.length);}
});

const saved=sessionStorage.getItem('mcserver-admin-token');
if(saved){tokenInput.value=saved;validateToken();}
