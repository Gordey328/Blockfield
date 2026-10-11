/* Blockfield browser exports. A visible link keeps the final save inside a
 * real user click even when map encoding/screenshot capture is asynchronous. */
(() => {
  let dialog, link, preview, title, detail, style, objectUrl, chunks = [], mime, filename;
  let pending = false;
  let closeCallback;
  let pointerCallback;
  document.addEventListener('pointerlockerror',()=>pointerCallback?.(false));
  document.addEventListener('pointerlockchange',()=>{if(document.pointerLockElement)pointerCallback?.(true);});
  function release() {
    if (objectUrl) URL.revokeObjectURL(objectUrl);
    objectUrl = undefined;
    chunks = [];
    pending = false;
    if (preview) preview.removeAttribute('src');
    if (link) {
      link.removeAttribute('href');
      link.removeAttribute('download');
    }
  }
  function abort() {
    closeCallback = undefined;
    const retiredDialog = dialog;
    // A queued close event from this dialog must not release a later begin().
    dialog = undefined;
    release();
    if (retiredDialog?.open) retiredDialog.close();
    retiredDialog?.remove();
    link = preview = title = detail = undefined;
    mime = filename = undefined;
  }
  function build() {
    if (dialog) return;
    if (!style) {
      style = document.createElement('style');
      style.textContent = `#blockfield-export{background:#152128;color:#eef3ee;border:1px solid #77958a;border-radius:8px;padding:20px;width:min(560px,85vw);font:16px system-ui,sans-serif}#blockfield-export::backdrop{background:#000a}#blockfield-export img{display:block;max-width:100%;max-height:50vh;margin:14px auto}#blockfield-export a,#blockfield-export button{display:inline-block;padding:10px 20px;background:#729b80;color:#fff;border:0;border-radius:4px;text-decoration:none;font:inherit;cursor:pointer;margin:6px 8px 0 0}#blockfield-export button{background:#344952}#blockfield-export p{overflow-wrap:anywhere}`;
      document.head.append(style);
    }
    dialog = document.createElement('dialog');
    const exportDialog = dialog;
    dialog.id = 'blockfield-export';
    title = document.createElement('h2');
    detail = document.createElement('p');
    preview = document.createElement('img');
    preview.alt = 'Blockfield screenshot';
    link = document.createElement('a');
    link.id = 'blockfield-export-download';
    const close = document.createElement('button');
    close.type = 'button';
    close.id = 'blockfield-export-close';
    close.addEventListener('click', () => exportDialog.close());
    dialog.addEventListener('close', () => {
      if (dialog !== exportDialog) return;
      release();
      const callback = closeCallback;
      closeCallback = undefined;
      if (callback) callback();
      document.getElementById('canvas')?.focus();
    });
    dialog.append(title, detail, preview, link, close);
    document.body.append(dialog);
  }
  window.BlockfieldExports = {
    setPointerCallback(callback) { pointerCallback=callback; },
    toggleFullscreen(callback) {
      try {
        const action=document.fullscreenElement ? document.exitFullscreen() : document.getElementById('canvas').requestFullscreen();
        Promise.resolve(action).then(()=>callback('')).catch(error=>callback(String(error.message||error)));
      } catch(error) { callback(String(error.message||error)); }
    },
    begin(name, type, callback) {
      abort();
      build();
      filename = name;
      mime = type;
      closeCallback = callback;
      pending = true;
    },
    append(base64) {
      if (!pending) return;
      const decoded = atob(base64);
      const bytes = new Uint8Array(decoded.length);
      for (let i = 0; i < decoded.length; ++i) bytes[i] = decoded.charCodeAt(i);
      chunks.push(bytes);
    },
    finish(locale) {
      if (!pending) return;
      const blob = new Blob(chunks, { type: mime });
      chunks = [];
      pending = false;
      objectUrl = URL.createObjectURL(blob);
      const russian = locale === 'ru';
      title.textContent = russian ? 'Файл готов' : 'File ready';
      detail.textContent = `${filename} · ${(blob.size / 1048576).toFixed(2)} MB`;
      link.textContent = russian ? 'Скачать' : 'Download';
      link.href = objectUrl;
      link.download = filename;
      document.getElementById('blockfield-export-close').textContent = russian ? 'Вернуться в игру' : 'Return to game';
      preview.hidden = mime !== 'image/png';
      preview.style.display = preview.hidden ? 'none' : 'block';
      if (!preview.hidden) preview.src = objectUrl;
      if (document.pointerLockElement) document.exitPointerLock();
      if (!dialog.open) dialog.showModal();
    },
    abort,
    clear() {
      pointerCallback=undefined;
      abort();
      style?.remove();
      style = undefined;
    }
  };
})();
