// Opt-in: node --test tests/browser/test_exports.mjs (no engine/browser needed).
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import test from 'node:test';
import vm from 'node:vm';

const source = readFileSync(new URL('../../game/web/exports.js', import.meta.url), 'utf8');
const base64 = bytes => Buffer.from(bytes).toString('base64');

function fixture() {
  const events = [];
  function eventTarget() {
    const listeners = new Map();
    return {
      addEventListener(type, callback) {
        const callbacks = listeners.get(type) ?? [];
        callbacks.push(callback);
        listeners.set(type, callbacks);
      },
      dispatch(type) { for (const callback of listeners.get(type) ?? []) callback(); }
    };
  }
  class Element {
    constructor(tag) {
      Object.assign(this, eventTarget());
      this.tag = tag;
      this.children = [];
      this.attributes = {};
      this.style = {};
      this.open = false;
      this.focusCount = 0;
    }
    append(...children) { for (const child of children) { child.parent = this; this.children.push(child); } }
    remove() {
      if (this.parent) this.parent.children = this.parent.children.filter(child => child !== this);
      this.parent = undefined;
    }
    removeAttribute(name) { delete this.attributes[name]; }
    set href(value) { this.attributes.href = value; }
    get href() { return this.attributes.href; }
    set download(value) { this.attributes.download = value; }
    get download() { return this.attributes.download; }
    set src(value) { this.attributes.src = value; }
    get src() { return this.attributes.src; }
    focus() { this.focusCount++; }
    showModal() { this.open = true; }
    close() {
      if (!this.open) return;
      this.open = false;
      // HTML dialog close events are queued: deliberately deliver after begin().
      events.push(() => this.dispatch('close'));
    }
  }
  const head = new Element('head');
  const body = new Element('body');
  const canvas = new Element('canvas');
  canvas.id = 'canvas';
  body.append(canvas);
  function find(element, id) {
    if (element.id === id) return element;
    for (const child of element.children) {
      const result = find(child, id);
      if (result) return result;
    }
  }
  const document = {
    ...eventTarget(), head, body,
    createElement: tag => new Element(tag),
    getElementById: id => find(body, id),
    exitPointerLock() { this.pointerLockElement = undefined; }
  };
  const liveUrls = new Map();
  const revoked = [];
  let nextUrl = 0;
  const window = {};
  vm.runInNewContext(source, {
    window, document, Blob, Uint8Array, atob, Promise,
    URL: {
      createObjectURL(blob) {
        const url = `blob:test-${++nextUrl}`;
        liveUrls.set(url, blob);
        return url;
      },
      revokeObjectURL(url) { revoked.push(url); liveUrls.delete(url); }
    }
  }, { filename: 'game/web/exports.js' });
  return {
    api: window.BlockfieldExports, document, canvas, liveUrls, revoked,
    flush() { while (events.length) events.shift()(); },
    link: () => document.getElementById('blockfield-export-download'),
    dialog: () => document.getElementById('blockfield-export')
  };
}

async function bytesAt(f, url) {
  return [...new Uint8Array(await f.liveUrls.get(url).arrayBuffer())];
}

test('binary chunks retain byte order and user close releases the Blob once', async () => {
  const f = fixture();
  let closes = 0;
  f.api.begin('ordered.vxl', 'application/octet-stream', () => closes++);
  f.api.append(base64([0, 255, 1]));
  f.api.append(base64([128, 0, 254, 2]));
  f.api.finish('ru');
  const link = f.link();
  const url = link.href;
  assert.equal(link.download, 'ordered.vxl');
  assert.equal(f.liveUrls.get(url).type, 'application/octet-stream');
  assert.deepEqual(await bytesAt(f, url), [0, 255, 1, 128, 0, 254, 2]);
  f.api.append('ignored after finish');
  f.api.finish('en');
  assert.equal(f.liveUrls.size, 1);
  assert.equal(f.link().href, url);
  f.document.getElementById('blockfield-export-close').dispatch('click');
  f.flush();
  f.flush();
  assert.equal(closes, 1);
  assert.deepEqual(f.revoked, [url]);
  assert.equal(link.href, undefined);
  assert.equal(f.canvas.focusCount, 1);
  f.api.clear();
  assert.equal(f.document.head.children.length, 0);
});

test('abort removes pending bytes and preserves pointer callback through stale close events', async () => {
  const f = fixture();
  let staleCloses = 0;
  let freshCloses = 0;
  const pointer = [];
  f.api.setPointerCallback(value => pointer.push(value));
  f.api.begin('partial.vxl', 'application/octet-stream', () => staleCloses++);
  f.api.append(base64([222, 173]));
  f.api.abort();
  f.api.append('ignored after abort');
  f.api.finish('en');
  assert.equal(f.liveUrls.size, 0);
  assert.equal(f.dialog(), undefined);
  f.document.dispatch('pointerlockerror');
  f.document.pointerLockElement = f.canvas;
  f.document.dispatch('pointerlockchange');
  assert.deepEqual(pointer, [false, true]);

  f.api.begin('old.png', 'image/png', () => staleCloses++);
  f.api.append(base64([9, 8]));
  f.api.finish('en');
  const oldDialog = f.dialog();
  const oldLink = f.link();
  const oldPreview = oldDialog.children.find(child => child.tag === 'img');
  const oldUrl = oldLink.href;
  assert.equal(oldPreview.src, oldUrl);
  f.api.abort();
  assert.equal(oldDialog.open, false);
  assert.equal(oldDialog.parent, undefined);
  assert.equal(oldPreview.src, undefined);
  assert.equal(oldLink.href, undefined);
  assert.equal(oldLink.download, undefined);
  assert.deepEqual(f.revoked, [oldUrl]);

  f.api.begin('fresh.vxl', 'application/octet-stream', () => freshCloses++);
  f.api.append(base64([7, 0, 6]));
  f.flush();
  f.api.finish('en');
  const freshUrl = f.link().href;
  assert.deepEqual(await bytesAt(f, freshUrl), [7, 0, 6]);
  assert.equal(staleCloses, 0);
  assert.equal(f.canvas.focusCount, 0);
  assert.equal(f.document.head.children.length, 1);
  f.dialog().close();
  f.flush();
  assert.equal(freshCloses, 1);
  assert.deepEqual(f.revoked, [oldUrl, freshUrl]);
});

test('replacing a completed export and scene clear cannot fire old callbacks', async () => {
  const f = fixture();
  let closes = 0;
  let pointerCalls = 0;
  f.api.setPointerCallback(() => pointerCalls++);
  f.api.begin('old.json', 'application/json', () => closes++);
  f.api.append(base64([123, 125]));
  f.api.finish('en');
  const oldUrl = f.link().href;
  f.api.begin('new.png', 'image/png', () => closes++);
  f.api.append(base64([1, 2, 3]));
  f.api.finish('en');
  const newUrl = f.link().href;
  f.flush();
  assert.deepEqual(await bytesAt(f, newUrl), [1, 2, 3]);
  assert.deepEqual(f.revoked, [oldUrl]);
  assert.equal(closes, 0);
  assert.equal(f.dialog().open, true);
  f.api.clear();
  f.flush();
  f.api.append('ignored after clear');
  f.api.finish('en');
  f.document.dispatch('pointerlockerror');
  assert.equal(closes, 0);
  assert.equal(pointerCalls, 0);
  assert.equal(f.liveUrls.size, 0);
  assert.deepEqual(f.revoked, [oldUrl, newUrl]);
  assert.equal(f.dialog(), undefined);
  assert.equal(f.document.head.children.length, 0);
});
