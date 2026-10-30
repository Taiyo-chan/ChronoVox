/* ChronoVox Web App (PWA) - Full Feature Parity with iOS App */

const state = {
  activeTab: 'record', // 'record' | 'triage' | 'projects' | 'settings'
  appLang: localStorage.getItem('CHRONOVOX_APP_LANG') || 'ja',
  transLang: localStorage.getItem('CHRONOVOX_TRANS_LANG') || 'auto',
  apiKey: localStorage.getItem('CHRONOVOX_GEMINI_KEY') || '',
  reasoningModel: localStorage.getItem('CHRONOVOX_MODEL') || 'gemini-3.8-flash',
  showApiKey: false,

  // Recording state
  recState: 'idle', // 'idle' | 'recording' | 'paused'
  elapsedSec: 0,
  sessionTakeCount: 0,
  waveformBars: new Array(44).fill(8),

  // Data from IndexedDB
  recordings: [], // { id, title, fileName, createdAt, duration, projectName, mimeType, blob }
  projects: [],   // { name, createdAt, overview, currentStatus }
  documents: [],  // { id, projectName, audioId, mode, title, fileName, content, updatedAt }

  // Navigation sub-states
  selectedProjectName: null,
  projectSubTab: 'audio', // 'audio' | 'docs' | 'context'
  selectedAudioIdForAI: null,
  selectedAIMode: 'meeting_minutes', // 'transcription' | 'speaker_diarization' | 'meeting_minutes'
  aiProcessing: false,
  aiStatusText: '',
  statusUpdatedBanner: false,

  // Audio player state
  playingId: null,
  isPlaying: false,
  playCurrentTime: 0,
  playDuration: 0,
  playbackRate: 1.0
};

let db = null;
let mediaRecorder = null;
let mediaStream = null;
let recordedChunks = [];
let recStartTimestamp = 0;
let recAccumulatedMs = 0;
let stopwatchInterval = null;
let audioCtx = null;
let analyserNode = null;
let audioElement = new Audio();
let activeObjectURL = null;

// ==================== IndexedDB Setup ====================
function openDatabase() {
  return new Promise((resolve, reject) => {
    const req = indexedDB.open('chronovox_web_db', 1);
    req.onupgradeneeded = (e) => {
      const d = e.target.result;
      if (!d.objectStoreNames.contains('recordings')) {
        d.createObjectStore('recordings', { keyPath: 'id' });
      }
      if (!d.objectStoreNames.contains('projects')) {
        d.createObjectStore('projects', { keyPath: 'name' });
      }
      if (!d.objectStoreNames.contains('documents')) {
        d.createObjectStore('documents', { keyPath: 'id' });
      }
    };
    req.onsuccess = (e) => resolve(e.target.result);
    req.onerror = (e) => reject(e.target.error);
  });
}

function dbGetAll(storeName) {
  return new Promise((resolve, reject) => {
    const tx = db.transaction(storeName, 'readonly');
    const req = tx.objectStore(storeName).getAll();
    req.onsuccess = () => resolve(req.result || []);
    req.onerror = () => reject(req.error);
  });
}

function dbPut(storeName, value) {
  return new Promise((resolve, reject) => {
    const tx = db.transaction(storeName, 'readwrite');
    tx.objectStore(storeName).put(value);
    tx.oncomplete = () => resolve();
    tx.onerror = () => reject(tx.error);
  });
}

function dbDelete(storeName, key) {
  return new Promise((resolve, reject) => {
    const tx = db.transaction(storeName, 'readwrite');
    tx.objectStore(storeName).delete(key);
    tx.oncomplete = () => resolve();
    tx.onerror = () => reject(tx.error);
  });
}

async function reloadAllData() {
  const [recs, projs, docs] = await Promise.all([
    dbGetAll('recordings'),
    dbGetAll('projects'),
    dbGetAll('documents')
  ]);
  state.recordings = recs.sort((a, b) => b.createdAt - a.createdAt);
  state.projects = projs.sort((a, b) => a.name.localeCompare(b.name));
  state.documents = docs.sort((a, b) => b.updatedAt - a.updatedAt);
  render();
}

// ==================== Helpers ====================
function t() {
  return I18N[state.appLang] || I18N.ja;
}

function getAppLangObj(code) {
  return APP_LANGUAGES.find((l) => l.code === code) || APP_LANGUAGES[0];
}

function formatDuration(sec) {
  const s = Math.max(0, Math.round(sec || 0));
  const hrs = Math.floor(s / 3600);
  const mins = Math.floor((s % 3600) / 60);
  const secs = s % 60;
  if (hrs > 0) {
    return `${hrs}:${String(mins).padStart(2, '0')}:${String(secs).padStart(2, '0')}`;
  }
  return `${String(mins).padStart(2, '0')}:${String(secs).padStart(2, '0')}`;
}

function formatStopwatch(sec) {
  const totalCs = Math.floor((sec || 0) * 100);
  const hrs = Math.floor(totalCs / 360000);
  const mins = Math.floor((totalCs % 360000) / 6000);
  const secs = Math.floor((totalCs % 6000) / 100);
  const cs = totalCs % 100;
  const main = hrs > 0
    ? `${hrs}:${String(mins).padStart(2, '0')}:${String(secs).padStart(2, '0')}`
    : `${String(mins).padStart(2, '0')}:${String(secs).padStart(2, '0')}`;
  return { main, sub: `.${String(cs).padStart(2, '0')}` };
}

function formatDate(ts) {
  const d = new Date(ts);
  const yyyy = d.getFullYear();
  const mm = String(d.getMonth() + 1).padStart(2, '0');
  const dd = String(d.getDate()).padStart(2, '0');
  const hh = String(d.getHours()).padStart(2, '0');
  const mi = String(d.getMinutes()).padStart(2, '0');
  return `${yyyy}/${mm}/${dd} ${hh}:${mi}`;
}

function escapeHtml(str) {
  return String(str || '')
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;');
}

function unassignedRecordings() {
  return state.recordings.filter((r) => !r.projectName);
}

// ==================== Recording & Continuous Session ====================
function supportedRecordingMimeType() {
  const candidates = ['audio/mp4', 'audio/aac', 'audio/webm;codecs=opus', 'audio/webm'];
  if (typeof MediaRecorder === 'undefined') return '';
  for (const m of candidates) {
    if (MediaRecorder.isTypeSupported && MediaRecorder.isTypeSupported(m)) {
      return m;
    }
  }
  return '';
}

async function startRecording() {
  stopPlayback();
  try {
    if (!mediaStream) {
      mediaStream = await navigator.mediaDevices.getUserMedia({ audio: true });
    }
    const mimeType = supportedRecordingMimeType();
    recordedChunks = [];
    mediaRecorder = mimeType
      ? new MediaRecorder(mediaStream, { mimeType })
      : new MediaRecorder(mediaStream);

    mediaRecorder.ondataavailable = (e) => {
      if (e.data && e.data.size > 0) {
        recordedChunks.push(e.data);
      }
    };

    // Setup WebAudio Analyser for real-time waveform
    audioCtx = new (window.AudioContext || window.webkitAudioContext)();
    const source = audioCtx.createMediaStreamSource(mediaStream);
    analyserNode = audioCtx.createAnalyser();
    analyserNode.fftSize = 128;
    source.connect(analyserNode);

    mediaRecorder.start(200);
    recStartTimestamp = performance.now();
    recAccumulatedMs = 0;
    state.elapsedSec = 0;
    state.recState = 'recording';
    state.waveformBars = new Array(44).fill(8);
    startStopwatchLoop();
    render();
  } catch (err) {
    alert('Microphone permission is required: ' + err.message);
  }
}

function pauseRecording() {
  if (state.recState !== 'recording' || !mediaRecorder) return;
  mediaRecorder.pause();
  recAccumulatedMs += performance.now() - recStartTimestamp;
  state.recState = 'paused';
  stopStopwatchLoop();
  render();
}

function resumeRecording() {
  if (state.recState !== 'paused' || !mediaRecorder) return;
  mediaRecorder.resume();
  recStartTimestamp = performance.now();
  state.recState = 'recording';
  startStopwatchLoop();
  render();
}

function finishCurrentRecording(startNextImmediately = false) {
  if (state.recState === 'idle' || !mediaRecorder) return;
  const totalMs = state.recState === 'recording'
    ? recAccumulatedMs + (performance.now() - recStartTimestamp)
    : recAccumulatedMs;
  const finalDurationSec = Math.max(0.5, totalMs / 1000);
  const usedMime = mediaRecorder.mimeType || 'audio/mp4';

  stopStopwatchLoop();
  if (audioCtx) {
    audioCtx.close().catch(() => {});
    audioCtx = null;
    analyserNode = null;
  }

  mediaRecorder.onstop = async () => {
    const blob = new Blob(recordedChunks, { type: usedMime });
    const ext = usedMime.includes('webm') ? 'webm' : 'm4a';
    const now = new Date();
    const stamp = `${now.getFullYear()}${String(now.getMonth() + 1).padStart(2, '0')}${String(now.getDate()).padStart(2, '0')}_${String(now.getHours()).padStart(2, '0')}${String(now.getMinutes()).padStart(2, '0')}${String(now.getSeconds()).padStart(2, '0')}`;
    state.sessionTakeCount += 1;
    const baseTitle = `Rec_${stamp}_Take${String(state.sessionTakeCount).padStart(2, '0')}`;

    const item = {
      id: 'rec_' + Date.now() + '_' + Math.random().toString(36).slice(2, 7),
      title: baseTitle,
      fileName: `${baseTitle}.${ext}`,
      createdAt: Date.now(),
      duration: finalDurationSec,
      projectName: null,
      mimeType: usedMime.split(';')[0] || 'audio/mp4',
      blob
    };

    await dbPut('recordings', item);
    state.recState = 'idle';
    state.elapsedSec = 0;
    await reloadAllData();

    if (startNextImmediately) {
      await startRecording();
    } else if (mediaStream) {
      mediaStream.getTracks().forEach((tr) => tr.stop());
      mediaStream = null;
    }
  };

  mediaRecorder.stop();
}

function startStopwatchLoop() {
  stopStopwatchLoop();
  const dataArray = new Uint8Array(64);
  stopwatchInterval = setInterval(() => {
    if (state.recState !== 'recording') return;
    const currentMs = recAccumulatedMs + (performance.now() - recStartTimestamp);
    state.elapsedSec = currentMs / 1000;

    if (analyserNode) {
      analyserNode.getByteFrequencyData(dataArray);
      let sum = 0;
      for (let i = 0; i < 24; i++) sum += dataArray[i];
      const avg = sum / 24; // 0..255
      const pct = Math.max(8, Math.min(100, Math.round((avg / 200) * 100)));
      state.waveformBars.shift();
      state.waveformBars.push(pct);
    }

    // Update stopwatch & waveform DOM directly for smooth 25fps without full re-render
    const swEl = document.getElementById('liveStopwatchDigits');
    if (swEl) {
      const sw = formatStopwatch(state.elapsedSec);
      swEl.innerHTML = `${sw.main}<span class="stopwatch-sub">${sw.sub}</span>`;
    }
    const wfEl = document.getElementById('liveWaveformBars');
    if (wfEl && wfEl.children.length === state.waveformBars.length) {
      for (let i = 0; i < state.waveformBars.length; i++) {
        wfEl.children[i].style.height = `${state.waveformBars[i]}%`;
      }
    }
  }, 40);
}

function stopStopwatchLoop() {
  if (stopwatchInterval) {
    clearInterval(stopwatchInterval);
    stopwatchInterval = null;
  }
}

// ==================== Audio Playback ====================
audioElement.addEventListener('timeupdate', () => {
  state.playCurrentTime = audioElement.currentTime;
  const slider = document.getElementById(`seek_${state.playingId}`);
  const timeLbl = document.getElementById(`time_${state.playingId}`);
  if (slider) slider.value = state.playCurrentTime;
  if (timeLbl) timeLbl.textContent = formatDuration(state.playCurrentTime);
});

audioElement.addEventListener('ended', () => {
  state.isPlaying = false;
  state.playCurrentTime = 0;
  render();
});

function togglePlayback(recId) {
  const item = state.recordings.find((r) => r.id === recId);
  if (!item || !item.blob) return;

  if (state.playingId === recId) {
    if (state.isPlaying) {
      audioElement.pause();
      state.isPlaying = false;
    } else {
      audioElement.playbackRate = state.playbackRate;
      audioElement.play();
      state.isPlaying = true;
    }
    render();
    return;
  }

  stopPlayback();
  activeObjectURL = URL.createObjectURL(item.blob);
  audioElement.src = activeObjectURL;
  audioElement.playbackRate = state.playbackRate;
  state.playingId = recId;
  state.playDuration = item.duration || 1;
  state.playCurrentTime = 0;
  audioElement.play();
  state.isPlaying = true;
  render();
}

function stopPlayback() {
  audioElement.pause();
  if (activeObjectURL) {
    URL.revokeObjectURL(activeObjectURL);
    activeObjectURL = null;
  }
  state.playingId = null;
  state.isPlaying = false;
  state.playCurrentTime = 0;
}

function skipPlayback(deltaSec) {
  if (!state.playingId) return;
  audioElement.currentTime = Math.max(0, Math.min(audioElement.duration || state.playDuration, audioElement.currentTime + deltaSec));
}

function changePlaybackRate(rate) {
  state.playbackRate = parseFloat(rate);
  audioElement.playbackRate = state.playbackRate;
  render();
}

// ==================== Project & Triage Operations ====================
async function createNewProject(name, overviewText = '', statusText = '') {
  const trimmed = (name || '').trim();
  if (!trimmed) return null;
  const existing = state.projects.find((p) => p.name === trimmed);
  if (existing) return existing;

  const defaultOverview = overviewText.trim() || `# 🗺️ Project Overview: ${trimmed}\n\n## Overview & Goals\n- (Write project goals, background, and key participants here)\n`;
  const defaultStatus = statusText.trim() || `# 📊 Current Status: ${trimmed}\n\n## 🟢 Current Phase\n- In Progress\n\n## 📝 Active Tasks\n- [ ] Initial setup\n`;

  const proj = {
    name: trimmed,
    createdAt: Date.now(),
    overview: defaultOverview,
    currentStatus: defaultStatus
  };
  await dbPut('projects', proj);
  await reloadAllData();
  return proj;
}

async function moveRecordingToProject(recId, projectName, openAIViewAfter = false) {
  const item = state.recordings.find((r) => r.id === recId);
  if (!item) return;
  item.projectName = projectName;
  await dbPut('recordings', item);
  await reloadAllData();

  if (openAIViewAfter) {
    state.activeTab = 'projects';
    state.selectedProjectName = projectName;
    state.projectSubTab = 'audio';
    state.selectedAudioIdForAI = recId;
    render();
  }
}

async function moveAllUnassignedToProject(projectName) {
  const items = unassignedRecordings();
  let lastId = null;
  for (const item of items) {
    item.projectName = projectName;
    lastId = item.id;
    await dbPut('recordings', item);
  }
  await reloadAllData();
  if (lastId) {
    state.activeTab = 'projects';
    state.selectedProjectName = projectName;
    state.projectSubTab = 'audio';
    state.selectedAudioIdForAI = lastId;
    render();
  }
}

async function deleteRecordingById(recId) {
  if (state.playingId === recId) stopPlayback();
  await dbDelete('recordings', recId);
  await reloadAllData();
}

function downloadBlob(blob, fileName) {
  const url = URL.createObjectURL(blob);
  const a = document.createElement('a');
  a.href = url;
  a.download = fileName;
  a.click();
  setTimeout(() => URL.revokeObjectURL(url), 1000);
}

// ==================== Gemini Interactions API ====================
function blobToBase64(blob) {
  return new Promise((resolve, reject) => {
    const reader = new FileReader();
    reader.onloadend = () => {
      const dataUrl = reader.result || '';
      const base64 = String(dataUrl).split(',')[1] || '';
      resolve(base64);
    };
    reader.onerror = reject;
    reader.readAsDataURL(blob);
  });
}

async function callGeminiInteractions(body) {
  const key = (state.apiKey || '').trim();
  if (!key) {
    throw new Error(t().apiKeyMissing);
  }
  const res = await fetch('https://generativelanguage.googleapis.com/v1beta/interactions', {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      'x-goog-api-key': key
    },
    body: JSON.stringify(body)
  });

  if (!res.ok) {
    const errText = await res.text();
    throw new Error(`Gemini API Error (${res.status}): ${errText}`);
  }

  const json = await res.json();
  if (json.output_text) return json.output_text;

  if (Array.isArray(json.steps)) {
    const texts = [];
    for (const step of json.steps) {
      if (step.type === 'model_output' && Array.isArray(step.content)) {
        for (const c of step.content) {
          if (c.type === 'text' && c.text) texts.push(c.text);
        }
      }
    }
    if (texts.length > 0) return texts.join('\n');
  }
  throw new Error('No text output returned from Gemini API.');
}

function buildProjectHistoricalContext(project, excludingAudioId) {
  const pastAudio = state.recordings
    .filter((r) => r.projectName === project.name && r.id !== excludingAudioId)
    .slice(0, 10)
    .map((r) => `- ${r.fileName} (${formatDate(r.createdAt)}, ${formatDuration(r.duration)})`)
    .join('\n');

  const projDocs = state.documents.filter((d) => d.projectName === project.name);
  const pastMinutes = projDocs
    .filter((d) => d.mode === 'meeting_minutes')
    .slice(0, 3)
    .map((d) => `### 📄 ${d.fileName} (${formatDate(d.updatedAt)})\n${String(d.content).slice(0, 3500)}`)
    .join('\n\n');

  const pastTranscripts = projDocs
    .filter((d) => d.mode !== 'meeting_minutes')
    .slice(0, 2)
    .map((d) => `### 🗣️ ${d.fileName} (${formatDate(d.updatedAt)})\n${String(d.content).slice(0, 2500)}`)
    .join('\n\n');

  return [
    `## 1. Project Overview (overview.md)\n${project.overview || '(Empty)'}`,
    `## 2. Current Status (current_status.md)\n${project.currentStatus || '(Empty)'}`,
    pastAudio ? `## 3. Past Audio Recordings in Project\n${pastAudio}` : '',
    pastMinutes ? `## 4. Past Meeting Minutes\n${pastMinutes}` : '',
    pastTranscripts ? `## 5. Past Transcripts\n${pastTranscripts}` : ''
  ].filter(Boolean).join('\n\n---\n\n');
}

async function runAIOperation(recItem, project, mode) {
  if (!state.apiKey.trim()) {
    alert(t().apiKeyMissing);
    state.activeTab = 'settings';
    render();
    return;
  }

  state.aiProcessing = true;
  state.aiStatusText = 'Processing audio with Gemini API...';
  render();

  try {
    const base64Audio = await blobToBase64(recItem.blob);
    const mimeType = recItem.mimeType || 'audio/mp4';
    const langOpt = TRANSCRIPTION_LANGUAGE_OPTIONS.find((o) => o.code === state.transLang) || TRANSCRIPTION_LANGUAGE_OPTIONS[0];
    const targetLangObj = getAppLangObj(state.transLang === 'auto' ? state.appLang : state.transLang);
    const langBadge = state.transLang === 'auto' ? 'Automatic' : `${targetLangObj.short} (${targetLangObj.bcp47})`;

    let finalMarkdown = '';

    if (mode === 'transcription') {
      try {
        const raw = await callGeminiInteractions({
          model: 'models/gemini-3.5-transcribe',
          input: [{ type: 'audio', data: base64Audio, mime_type: mimeType }],
          generation_config: {
            transcription_config: {
              mode: 'smart',
              language_codes: langOpt.bcp47
            }
          }
        });
        finalMarkdown = `# 📝 Transcription: ${recItem.title}\n\n- **Project**: ${project.name}\n- **Audio**: \`${recItem.fileName}\`\n- **Language**: ${langBadge}\n\n---\n\n${raw}`;
      } catch (_) {
        const fallback = await callGeminiInteractions({
          model: state.reasoningModel,
          input: [
            { type: 'audio', data: base64Audio, mime_type: mimeType },
            { type: 'text', text: `Transcribe this audio cleanly into readable paragraphs with filler words removed. Output language: ${targetLangObj.promptName}.` }
          ]
        });
        finalMarkdown = `# 📝 Transcription: ${recItem.title}\n\n- **Project**: ${project.name}\n- **Audio**: \`${recItem.fileName}\`\n- **Language**: ${langBadge}\n\n---\n\n${fallback}`;
      }
    } else if (mode === 'speaker_diarization') {
      let rawDiarized = '';
      try {
        rawDiarized = await callGeminiInteractions({
          model: 'models/gemini-3.5-transcribe',
          input: [{ type: 'audio', data: base64Audio, mime_type: mimeType }],
          generation_config: {
            transcription_config: {
              language_codes: langOpt.bcp47,
              mode: { type: 'verbatim', diarization_mode: 'speaker' }
            }
          }
        });
      } catch (_) {}

      const prompt = rawDiarized
        ? `Format the following speaker-diarized transcript into clean Markdown by speaker in ${targetLangObj.promptName}, matching participant names from overview.md where possible:\n\n[overview.md]\n${project.overview}\n\n[Raw Diarized Transcript]\n${rawDiarized}`
        : `Listen to this audio and transcribe it separated by speaker (Speaker A, Speaker B, or participant names from overview.md) in ${targetLangObj.promptName}.\n\n[overview.md]\n${project.overview}`;

      const formatted = await callGeminiInteractions({
        model: state.reasoningModel,
        input: rawDiarized
          ? [{ type: 'text', text: prompt }]
          : [{ type: 'audio', data: base64Audio, mime_type: mimeType }, { type: 'text', text: prompt }]
      });

      finalMarkdown = `# 👥 Speaker-Separated Transcript: ${recItem.title}\n\n- **Project**: ${project.name}\n- **Audio**: \`${recItem.fileName}\`\n- **Language**: ${langBadge}\n\n---\n\n${formatted}`;
    } else {
      // Context-Aware Meeting Minutes
      const historicalContext = buildProjectHistoricalContext(project, recItem.id);
      const prompt = `Using the [Project Historical Context] below (overview.md, current_status.md, past audio & minutes), analyze the attached audio recording and generate comprehensive Context-Aware Meeting Minutes in **${targetLangObj.promptName}**.\n\nInclude:\n1. 📌 Executive Summary\n2. 🔗 Progress & Changes from Previous Context (current_status.md & Past Minutes)\n3. 💬 Key Discussion Points\n4. ✅ Decisions Made\n5. 🚀 Next Actions & TODOs\n6. 📊 Suggested Updates to current_status.md\n\n---\n\n# [Project Historical Context]\n${historicalContext}`;

      const minutesBody = await callGeminiInteractions({
        model: state.reasoningModel,
        system_instruction: `You are the Project Manager & Secretary for "${project.name}". Write the meeting minutes in ${targetLangObj.promptName}.`,
        input: [
          { type: 'audio', data: base64Audio, mime_type: mimeType },
          { type: 'text', text: prompt }
        ]
      });

      finalMarkdown = `# 📋 Context-Aware Meeting Minutes: ${recItem.title}\n\n- **Project**: ${project.name}\n- **Audio**: \`${recItem.fileName}\`\n- **Language**: ${targetLangObj.short}\n- **Model**: \`${state.reasoningModel}\`\n\n---\n\n${minutesBody}`;
    }

    const docId = `${project.name}__${recItem.id}__${mode}`;
    const suffix = mode === 'meeting_minutes' ? '_minutes.md' : mode === 'speaker_diarization' ? '_diarized.md' : '_transcript.md';
    const docRecord = {
      id: docId,
      projectName: project.name,
      audioId: recItem.id,
      mode,
      title: `${recItem.title}${suffix.replace('.md', '')}`,
      fileName: `${recItem.title}${suffix}`,
      content: finalMarkdown,
      updatedAt: Date.now()
    };

    await dbPut('documents', docRecord);
    await reloadAllData();
  } catch (err) {
    alert(err.message);
  } finally {
    state.aiProcessing = false;
    state.aiStatusText = '';
    render();
  }
}

async function autoUpdateProjectStatus(project, latestMinutesContent) {
  state.aiProcessing = true;
  state.aiStatusText = 'Updating current_status.md...';
  render();
  try {
    const targetLangObj = getAppLangObj(state.transLang === 'auto' ? state.appLang : state.transLang);
    const updatedStatus = await callGeminiInteractions({
      model: state.reasoningModel,
      system_instruction: `Output only the updated Markdown for current_status.md in ${targetLangObj.promptName}.`,
      input: [
        {
          type: 'text',
          text: `Update current_status.md for project "${project.name}" in ${targetLangObj.promptName} based on:\n\n[overview.md]\n${project.overview}\n\n[Previous current_status.md]\n${project.currentStatus}\n\n[Latest Meeting Minutes]\n${latestMinutesContent}`
        }
      ]
    });
    project.currentStatus = updatedStatus;
    await dbPut('projects', project);
    state.statusUpdatedBanner = true;
    await reloadAllData();
    setTimeout(() => {
      state.statusUpdatedBanner = false;
      render();
    }, 3000);
  } catch (err) {
    alert(err.message);
  } finally {
    state.aiProcessing = false;
    state.aiStatusText = '';
    render();
  }
}

// ==================== UI Rendering ====================
function renderPlayerWidget(item) {
  const isPlayingThis = state.playingId === item.id;
  return `
    <div class="player-controls-bar">
      <button class="btn btn-secondary" onclick="togglePlayback('${item.id}')">
        ${isPlayingThis && state.isPlaying ? '⏸' : '▶️'}
      </button>
      ${isPlayingThis ? `
        <button class="btn btn-secondary" onclick="skipPlayback(-15)">-15s</button>
        <input id="seek_${item.id}" type="range" min="0" max="${Math.max(0.1, item.duration)}" step="0.1" value="${state.playCurrentTime}" oninput="audioElement.currentTime = parseFloat(this.value)" />
        <button class="btn btn-secondary" onclick="skipPlayback(15)">+15s</button>
        <select class="lang-quick-select" onchange="changePlaybackRate(this.value)">
          ${[0.75, 1.0, 1.25, 1.5, 2.0].map((r) => `<option value="${r}" ${state.playbackRate === r ? 'selected' : ''}>${r}x</option>`).join('')}
        </select>
      ` : `
        <span id="time_${item.id}" class="clip-meta" style="flex:1">${formatDate(item.createdAt)} • ${formatDuration(item.duration)}</span>
      `}
    </div>
  `;
}

function renderRecorderTab() {
  const tr = t();
  const sw = formatStopwatch(state.elapsedSec);
  const unassigned = unassignedRecordings();
  const badgeClass = state.recState === 'recording' ? 'recording' : state.recState === 'paused' ? 'paused' : '';
  const badgeText = state.recState === 'recording'
    ? tr.recordingBadge(state.sessionTakeCount + 1)
    : state.recState === 'paused'
      ? tr.pausedBadge
      : unassigned.length > 0
        ? tr.standbySessionBadge(unassigned.length)
        : tr.standbyBadge;

  return `
    <div class="stopwatch-card">
      <div class="status-pill ${badgeClass}">${escapeHtml(badgeText)}</div>
      <div id="liveStopwatchDigits" class="stopwatch-digits ${state.recState === 'recording' ? 'recording' : ''}">
        ${sw.main}<span class="stopwatch-sub">${sw.sub}</span>
      </div>
      <div id="liveWaveformBars" class="waveform-bars ${badgeClass}">
        ${state.waveformBars.map((h) => `<div class="waveform-bar" style="height:${h}%"></div>`).join('')}
      </div>

      <div class="record-controls">
        <div class="ctrl-col">
          <button class="circle-btn" ${state.recState === 'idle' ? 'disabled' : ''} onclick="${state.recState === 'paused' ? 'resumeRecording()' : 'pauseRecording()'}">
            ${state.recState === 'paused' ? '▶' : '⏸'}
          </button>
          <span class="ctrl-label">${escapeHtml(state.recState === 'paused' ? tr.resumeBtn : tr.pauseBtn)}</span>
        </div>

        <div class="ctrl-col">
          <button class="red-record-outer ${state.recState !== 'idle' ? 'active' : ''}" onclick="${state.recState === 'idle' ? 'startRecording()' : 'finishCurrentRecording(false)'}">
            <div class="red-record-inner"></div>
          </button>
          <span class="ctrl-label" style="color:${state.recState === 'idle' ? '#f87171' : '#f8fafc'}">
            ${escapeHtml(state.recState === 'idle' ? tr.startBtn : tr.finishClipBtn)}
          </span>
        </div>

        <div class="ctrl-col">
          <button class="circle-btn" ${state.recState === 'idle' ? 'disabled' : ''} onclick="finishCurrentRecording(true)">
            ⏭
          </button>
          <span class="ctrl-label">${escapeHtml(tr.splitNextBtn)}</span>
        </div>
      </div>

      ${state.recState === 'idle' && unassigned.length > 0 ? `<div class="hint-text">${escapeHtml(tr.continuousHint)}</div>` : ''}
    </div>

    <div class="section-header">
      <span class="section-title">🎙️ ${escapeHtml(tr.unassignedHeader(unassigned.length))}</span>
      ${unassigned.length > 0 ? `<button class="btn btn-primary" onclick="switchTab('triage')">${escapeHtml(tr.finishSessionBtn)}</button>` : ''}
    </div>

    ${unassigned.length === 0 ? `
      <div class="card" style="text-align:center; padding:28px 18px; color:var(--text-muted)">
        <div style="font-size:2rem; margin-bottom:8px">🎙️</div>
        <div style="font-weight:700; color:var(--text); margin-bottom:6px">${escapeHtml(tr.emptyRecordingsTitle)}</div>
        <div style="font-size:0.82rem">${escapeHtml(tr.emptyRecordingsSub)}</div>
      </div>
    ` : unassigned.map((item) => `
      <div class="card clip-row">
        <div class="clip-top">
          <div>
            <div class="clip-title">${escapeHtml(item.title)}</div>
          </div>
          <button class="btn btn-primary" onclick="switchTab('triage')">📁 ${escapeHtml(tr.tabTriage)}</button>
        </div>
        ${renderPlayerWidget(item)}
      </div>
    `).join('')}
  `;
}

function renderTriageTab() {
  const tr = t();
  const unassigned = unassignedRecordings();
  if (unassigned.length === 0) {
    return `
      <div class="card" style="text-align:center; padding:36px 20px">
        <div style="font-size:2.6rem; margin-bottom:10px">✅</div>
        <div style="font-weight:800; font-size:1.05rem; margin-bottom:8px">${escapeHtml(tr.allTriageDoneTitle)}</div>
        <div style="font-size:0.84rem; color:var(--text-muted); margin-bottom:16px">${escapeHtml(tr.allTriageDoneSub)}</div>
        <button class="btn btn-primary" onclick="switchTab('projects')">📁 ${escapeHtml(tr.tabProjects)}</button>
      </div>
    `;
  }

  return `
    <div class="card" style="background:var(--bg-elevated)">
      <div style="display:flex; justify-content:space-between; align-items:center; gap:12px; flex-wrap:wrap">
        <div>
          <div style="font-weight:800; font-size:0.95rem">${escapeHtml(tr.batchTitle)}</div>
          <div style="font-size:0.78rem; color:var(--text-muted)">${escapeHtml(tr.batchSub(unassigned.length))}</div>
        </div>
        <select class="select" style="width:auto" onchange="handleBatchProjectSelect(this.value)">
          <option value="">📦 ${escapeHtml(tr.batchBtn)}...</option>
          ${state.projects.map((p) => `<option value="${escapeHtml(p.name)}">📁 ${escapeHtml(p.name)}</option>`).join('')}
          <option value="__new__">${escapeHtml(tr.createNewProjectAndStore)}</option>
        </select>
      </div>
    </div>

    <div style="font-size:0.78rem; color:var(--text-muted); margin: 0 4px 12px">${escapeHtml(tr.triageFooter)}</div>

    ${unassigned.map((item) => `
      <div class="card clip-row">
        <div class="clip-top">
          <div class="clip-title">${escapeHtml(item.title)}</div>
          <button class="btn btn-secondary" onclick="promptRenameRecording('${item.id}')">✏️</button>
        </div>
        ${renderPlayerWidget(item)}
        <div class="action-row">
          <button class="btn btn-danger" onclick="deleteRecordingById('${item.id}')">🗑️ ${escapeHtml(tr.deleteBtn)}</button>
          <select class="select" onchange="handleSingleProjectSelect('${item.id}', this.value)">
            <option value="">📁 ${escapeHtml(tr.assignToProjectBtn)}...</option>
            ${state.projects.map((p) => `<option value="${escapeHtml(p.name)}">📁 ${escapeHtml(p.name)} (+ AI)</option>`).join('')}
            <option value="__new__">${escapeHtml(tr.createNewProjectAndStore)}</option>
          </select>
        </div>
      </div>
    `).join('')}
  `;
}

function renderProjectsTab() {
  const tr = t();

  // 1. Audio AI Action Sub-screen
  if (state.selectedProjectName && state.selectedAudioIdForAI) {
    const project = state.projects.find((p) => p.name === state.selectedProjectName);
    const item = state.recordings.find((r) => r.id === state.selectedAudioIdForAI);
    if (project && item) {
      return renderAudioAIActionScreen(project, item, tr);
    }
  }

  // 2. Project Detail Sub-screen
  if (state.selectedProjectName) {
    const project = state.projects.find((p) => p.name === state.selectedProjectName);
    if (project) {
      return renderProjectDetailScreen(project, tr);
    }
  }

  // 3. Project List Screen
  return `
    <div class="section-header">
      <span class="section-title">📁 ${escapeHtml(tr.projectsTitle)} (${state.projects.length})</span>
      <button class="btn btn-primary" onclick="openNewProjectModal()">${escapeHtml(tr.newProjectBtn)}</button>
    </div>
    <div style="font-size:0.78rem; color:var(--text-muted); margin: 0 4px 12px">${escapeHtml(tr.projectsFooter)}</div>

    ${state.projects.length === 0 ? `
      <div class="card" style="text-align:center; padding:32px 18px">
        <div style="font-size:2.4rem; margin-bottom:8px">📂</div>
        <div style="font-size:0.85rem; color:var(--text-muted); margin-bottom:14px">${escapeHtml(tr.projectsFooter)}</div>
        <button class="btn btn-primary" onclick="openNewProjectModal()">${escapeHtml(tr.newProjectBtn)}</button>
      </div>
    ` : state.projects.map((proj) => {
      const audioCount = state.recordings.filter((r) => r.projectName === proj.name).length;
      const docCount = state.documents.filter((d) => d.projectName === proj.name).length;
      return `
        <div class="card" style="cursor:pointer" onclick="openProject('${escapeHtml(proj.name)}')">
          <div style="display:flex; justify-content:space-between; align-items:center">
            <div>
              <div style="font-weight:800; font-size:1.05rem">📁 ${escapeHtml(proj.name)}</div>
              <div class="clip-meta" style="margin-top:4px">🎙️ ${audioCount} audio • 📋 ${docCount} docs</div>
            </div>
            <span style="color:var(--text-muted); font-size:1.2rem">›</span>
          </div>
        </div>
      `;
    }).join('')}
  `;
}

function renderProjectDetailScreen(project, tr) {
  const projAudio = state.recordings.filter((r) => r.projectName === project.name);
  const projDocs = state.documents.filter((d) => d.projectName === project.name);

  return `
    <div style="display:flex; align-items:center; justify-content:space-between; margin-bottom:12px">
      <button class="btn btn-secondary" onclick="state.selectedProjectName = null; render()">${escapeHtml(tr.backBtn)}</button>
      <strong style="font-size:1.05rem">📁 ${escapeHtml(project.name)}</strong>
      <span></span>
    </div>

    <div class="segmented">
      <button class="${state.projectSubTab === 'audio' ? 'active' : ''}" onclick="state.projectSubTab='audio'; render()">${escapeHtml(tr.secAudioAI)}</button>
      <button class="${state.projectSubTab === 'docs' ? 'active' : ''}" onclick="state.projectSubTab='docs'; render()">${escapeHtml(tr.secDocs)}</button>
      <button class="${state.projectSubTab === 'context' ? 'active' : ''}" onclick="state.projectSubTab='context'; render()">${escapeHtml(tr.secContext)}</button>
    </div>

    ${state.projectSubTab === 'audio' ? (
      projAudio.length === 0 ? `
        <div class="card" style="text-align:center; padding:28px; color:var(--text-muted)">No audio files stored in this project yet.</div>
      ` : projAudio.map((item) => {
        const hasTrans = projDocs.some((d) => d.audioId === item.id && d.mode === 'transcription');
        const hasDiar = projDocs.some((d) => d.audioId === item.id && d.mode === 'speaker_diarization');
        const hasMin = projDocs.some((d) => d.audioId === item.id && d.mode === 'meeting_minutes');
        return `
          <div class="card clip-row">
            <div class="clip-top">
              <div>
                <div class="clip-title">${escapeHtml(item.title)}</div>
                <div class="clip-meta">${formatDate(item.createdAt)} • ${formatDuration(item.duration)}</div>
              </div>
              <button class="btn btn-primary" onclick="state.selectedAudioIdForAI='${item.id}'; render()">✨ AI処理 / 議事録 ›</button>
            </div>
            <div style="display:flex; gap:6px; flex-wrap:wrap">
              <span class="pill ${hasTrans ? 'done' : ''}">${hasTrans ? '✓ ' : ''}${escapeHtml(tr.modeTranscription.replace(/^[・•]\s*/, ''))}</span>
              <span class="pill ${hasDiar ? 'done' : ''}">${hasDiar ? '✓ ' : ''}${escapeHtml(tr.modeDiarization.replace(/^[・•]\s*/, ''))}</span>
              <span class="pill ${hasMin ? 'done' : ''}">${hasMin ? '✓ ' : ''}${escapeHtml(tr.modeMinutes.replace(/^[・•]\s*/, ''))}</span>
            </div>
          </div>
        `;
      }).join('')
    ) : state.projectSubTab === 'docs' ? (
      projDocs.length === 0 ? `
        <div class="card" style="text-align:center; padding:28px; color:var(--text-muted)">No generated transcripts or meeting minutes yet.</div>
      ` : projDocs.map((doc) => `
        <div class="card">
          <div style="display:flex; justify-content:space-between; align-items:center; margin-bottom:8px">
            <strong>${escapeHtml(doc.fileName)}</strong>
            <button class="btn btn-secondary" onclick="downloadMarkdownDoc('${escapeHtml(doc.id)}')">⬇️ .md</button>
          </div>
          <textarea class="textarea" onchange="updateDocContent('${escapeHtml(doc.id)}', this.value)">${escapeHtml(doc.content)}</textarea>
        </div>
      `).join('')
    ) : `
      <div class="card">
        <div style="font-weight:700; margin-bottom:6px">🗺️ overview.md</div>
        <textarea id="projOverviewInput" class="textarea">${escapeHtml(project.overview)}</textarea>
        <div style="font-weight:700; margin:14px 0 6px">📊 current_status.md</div>
        <textarea id="projStatusInput" class="textarea">${escapeHtml(project.currentStatus)}</textarea>
        <button class="btn btn-primary btn-block" style="margin-top:12px" onclick="saveProjectContext('${escapeHtml(project.name)}')">💾 ${escapeHtml(tr.saveBtn)}</button>
      </div>
    `}
  `;
}

function renderAudioAIActionScreen(project, item, tr) {
  const modes = [
    { key: 'transcription', title: tr.modeTranscription, sub: tr.modeTranscriptionSub },
    { key: 'speaker_diarization', title: tr.modeDiarization, sub: tr.modeDiarizationSub },
    { key: 'meeting_minutes', title: tr.modeMinutes, sub: tr.modeMinutesSub }
  ];
  const currentDocId = `${project.name}__${item.id}__${state.selectedAIMode}`;
  const currentDoc = state.documents.find((d) => d.id === currentDocId);
  const selectedModeMeta = modes.find((m) => m.key === state.selectedAIMode) || modes[2];

  return `
    <div style="display:flex; align-items:center; justify-content:space-between; margin-bottom:12px">
      <button class="btn btn-secondary" onclick="state.selectedAudioIdForAI = null; render()">${escapeHtml(tr.backBtn)}</button>
      <strong style="font-size:0.95rem">📁 ${escapeHtml(project.name)}</strong>
      <button class="btn btn-secondary" onclick="downloadAudioItem('${item.id}')">⬇️ Audio</button>
    </div>

    <div class="card clip-row">
      <div class="clip-title">🎙️ ${escapeHtml(item.fileName)}</div>
      ${renderPlayerWidget(item)}
    </div>

    <div class="section-header">
      <span class="section-title">${escapeHtml(tr.selectAIHeader)}</span>
    </div>

    ${modes.map((m) => {
      const exists = state.documents.some((d) => d.id === `${project.name}__${item.id}__${m.key}`);
      return `
        <div class="mode-card ${state.selectedAIMode === m.key ? 'selected' : ''}" onclick="state.selectedAIMode='${m.key}'; render()">
          <div class="mode-card-title">
            <span>${escapeHtml(m.title)}</span>
            ${exists ? '<span class="pill done">✓</span>' : ''}
          </div>
          <div class="mode-card-sub">${escapeHtml(m.sub)}</div>
        </div>
      `;
    }).join('')}

    <div class="card" style="margin-top:10px">
      <div style="display:flex; justify-content:space-between; align-items:center; gap:10px; margin-bottom:10px">
        <span style="font-size:0.84rem; font-weight:700">🌐 ${escapeHtml(tr.audioLangLabel)}</span>
        <select class="select" style="width:auto" onchange="setTransLang(this.value)">
          <option value="auto" ${state.transLang === 'auto' ? 'selected' : ''}>${escapeHtml(tr.autoDetectLabel)}</option>
          ${APP_LANGUAGES.map((l) => `<option value="${l.code}" ${state.transLang === l.code ? 'selected' : ''}>${escapeHtml(l.label)} (${l.bcp47})</option>`).join('')}
        </select>
      </div>
      <div style="font-size:0.75rem; color:var(--text-muted); margin-bottom:12px">
        🧠 ${escapeHtml(tr.contextRefNotice)}
      </div>

      <button class="btn btn-primary btn-block" ${state.aiProcessing ? 'disabled' : ''} onclick="triggerAIRun()">
        ${state.aiProcessing ? `⏳ ${escapeHtml(state.aiStatusText)}` : escapeHtml(tr.runAIBtn(selectedModeMeta.title))}
      </button>
    </div>

    ${currentDoc ? `
      <div class="card">
        <div style="display:flex; justify-content:space-between; align-items:center; margin-bottom:8px">
          <strong>📄 ${escapeHtml(currentDoc.fileName)}</strong>
          <button class="btn btn-secondary" onclick="downloadMarkdownDoc('${escapeHtml(currentDoc.id)}')">⬇️ ${escapeHtml(tr.downloadBtn)}</button>
        </div>
        <textarea class="textarea" style="min-height:280px" onchange="updateDocContent('${escapeHtml(currentDoc.id)}', this.value)">${escapeHtml(currentDoc.content)}</textarea>

        ${state.selectedAIMode === 'meeting_minutes' ? `
          <button class="btn btn-warning btn-block" style="margin-top:10px" ${state.aiProcessing ? 'disabled' : ''} onclick="triggerStatusAutoUpdate()">
            ${escapeHtml(state.statusUpdatedBanner ? tr.updatedStatusDone : tr.updateStatusBtn)}
          </button>
        ` : ''}
      </div>
    ` : ''}
  `;
}

function renderSettingsTab() {
  const tr = t();
  return `
    <div class="card">
      <div style="font-weight:800; margin-bottom:10px">🌐 ${escapeHtml(tr.settingsLangHeader)}</div>
      <div style="margin-bottom:10px">
        <label style="font-size:0.8rem; color:var(--text-muted); display:block; margin-bottom:4px">${escapeHtml(tr.appLangLabel)}</label>
        <select class="select" onchange="setAppLang(this.value)">
          ${APP_LANGUAGES.map((l) => `<option value="${l.code}" ${state.appLang === l.code ? 'selected' : ''}>${escapeHtml(l.label)}</option>`).join('')}
        </select>
      </div>
      <div>
        <label style="font-size:0.8rem; color:var(--text-muted); display:block; margin-bottom:4px">${escapeHtml(tr.transLangLabel)}</label>
        <select class="select" onchange="setTransLang(this.value)">
          <option value="auto" ${state.transLang === 'auto' ? 'selected' : ''}>${escapeHtml(tr.autoDetectLabel)}</option>
          ${APP_LANGUAGES.map((l) => `<option value="${l.code}" ${state.transLang === l.code ? 'selected' : ''}>${escapeHtml(l.label)} (${l.bcp47})</option>`).join('')}
        </select>
      </div>
      <div style="font-size:0.75rem; color:var(--text-muted); margin-top:8px">${escapeHtml(tr.settingsLangFooter)}</div>
    </div>

    <div class="card">
      <div style="font-weight:800; margin-bottom:10px">🔑 ${escapeHtml(tr.apiKeyHeader)}</div>
      <div style="display:flex; gap:8px; margin-bottom:8px">
        <input
          type="${state.showApiKey ? 'text' : 'password'}"
          class="input"
          placeholder="AIzaSy..."
          value="${escapeHtml(state.apiKey)}"
          oninput="setApiKey(this.value)"
        />
        <button class="btn btn-secondary" onclick="state.showApiKey=!state.showApiKey; render()">
          ${state.showApiKey ? '🙈' : '👁️'}
        </button>
      </div>
      <div style="font-size:0.8rem; margin-bottom:10px">
        ${escapeHtml(state.apiKey.trim() ? tr.apiKeySet : tr.apiKeyMissing)}
      </div>
      <a href="https://aistudio.google.com/apikey" target="_blank" rel="noopener noreferrer" class="btn btn-secondary btn-block">
        ${escapeHtml(tr.getApiKeyLink)} ↗
      </a>
      <div style="font-size:0.75rem; color:var(--text-muted); margin-top:8px">${escapeHtml(tr.apiKeyFooter)}</div>
    </div>

    <div class="card">
      <div style="font-weight:800; margin-bottom:10px">🤖 ${escapeHtml(tr.modelHeader)}</div>
      <label style="font-size:0.8rem; color:var(--text-muted); display:block; margin-bottom:4px">${escapeHtml(tr.modelLabel)}</label>
      <select class="select" onchange="setReasoningModel(this.value)">
        <option value="gemini-3.8-flash" ${state.reasoningModel === 'gemini-3.8-flash' ? 'selected' : ''}>Gemini 3.8 Flash</option>
        <option value="gemini-4-argon" ${state.reasoningModel === 'gemini-4-argon' ? 'selected' : ''}>Gemini 4 Argon</option>
      </select>
      <div style="font-size:0.75rem; color:var(--text-muted); margin-top:8px">${escapeHtml(tr.modelFooter)}</div>
    </div>

    <div class="card">
      <div style="font-weight:800; margin-bottom:6px">${escapeHtml(tr.pwaGuideHeader)}</div>
      <div style="font-size:0.8rem; color:var(--text-muted); line-height:1.5">${escapeHtml(tr.pwaGuideBody)}</div>
    </div>
  `;
}

// ==================== Event Handlers ====================
function switchTab(tab) {
  state.activeTab = tab;
  if (tab !== 'projects') {
    state.selectedAudioIdForAI = null;
  }
  render();
}

function setAppLang(code) {
  state.appLang = code;
  localStorage.setItem('CHRONOVOX_APP_LANG', code);
  render();
}

function setTransLang(code) {
  state.transLang = code;
  localStorage.setItem('CHRONOVOX_TRANS_LANG', code);
  render();
}

function setApiKey(val) {
  state.apiKey = val;
  localStorage.setItem('CHRONOVOX_GEMINI_KEY', val);
}

function setReasoningModel(val) {
  state.reasoningModel = val;
  localStorage.setItem('CHRONOVOX_MODEL', val);
  render();
}

async function promptRenameRecording(recId) {
  const item = state.recordings.find((r) => r.id === recId);
  if (!item) return;
  const next = prompt('Rename recording:', item.title);
  if (next && next.trim()) {
    const ext = item.fileName.split('.').pop() || 'm4a';
    item.title = next.trim();
    item.fileName = `${item.title}.${ext}`;
    await dbPut('recordings', item);
    await reloadAllData();
  }
}

async function handleSingleProjectSelect(recId, value) {
  if (!value) return;
  if (value === '__new__') {
    const name = prompt('New Project Name:');
    if (!name || !name.trim()) {
      render();
      return;
    }
    const proj = await createNewProject(name.trim());
    if (proj) {
      await moveRecordingToProject(recId, proj.name, true);
    }
  } else {
    await moveRecordingToProject(recId, value, true);
  }
}

async function handleBatchProjectSelect(value) {
  if (!value) return;
  if (value === '__new__') {
    const name = prompt('New Project Name:');
    if (!name || !name.trim()) {
      render();
      return;
    }
    const proj = await createNewProject(name.trim());
    if (proj) {
      await moveAllUnassignedToProject(proj.name);
    }
  } else {
    await moveAllUnassignedToProject(value);
  }
}

function openNewProjectModal() {
  const tr = t();
  const modal = document.getElementById('modalContainer');
  modal.innerHTML = `
    <div class="modal-backdrop" onclick="if(event.target===this) closeModal()">
      <div class="modal-card">
        <div style="font-weight:800; font-size:1.05rem; margin-bottom:12px">${escapeHtml(tr.newProjectBtn)}</div>
        <input id="newProjName" class="input" placeholder="Project Name" style="margin-bottom:10px" />
        <textarea id="newProjOverview" class="textarea" placeholder="overview.md (optional)" style="min-height:100px; margin-bottom:12px"></textarea>
        <div class="action-row">
          <button class="btn btn-secondary" onclick="closeModal()">${escapeHtml(tr.cancelBtn)}</button>
          <button class="btn btn-primary" onclick="confirmCreateProjectModal()">${escapeHtml(tr.saveBtn)}</button>
        </div>
      </div>
    </div>
  `;
}

function closeModal() {
  document.getElementById('modalContainer').innerHTML = '';
}

async function confirmCreateProjectModal() {
  const name = document.getElementById('newProjName')?.value || '';
  const overview = document.getElementById('newProjOverview')?.value || '';
  if (!name.trim()) return;
  await createNewProject(name, overview);
  closeModal();
}

function openProject(name) {
  state.selectedProjectName = name;
  state.selectedAudioIdForAI = null;
  state.projectSubTab = 'audio';
  render();
}

async function saveProjectContext(projectName) {
  const proj = state.projects.find((p) => p.name === projectName);
  if (!proj) return;
  proj.overview = document.getElementById('projOverviewInput')?.value || '';
  proj.currentStatus = document.getElementById('projStatusInput')?.value || '';
  await dbPut('projects', proj);
  await reloadAllData();
}

async function updateDocContent(docId, newText) {
  const doc = state.documents.find((d) => d.id === docId);
  if (!doc) return;
  doc.content = newText;
  doc.updatedAt = Date.now();
  await dbPut('documents', doc);
}

function downloadMarkdownDoc(docId) {
  const doc = state.documents.find((d) => d.id === docId);
  if (!doc) return;
  const blob = new Blob([doc.content], { type: 'text/markdown;charset=utf-8' });
  downloadBlob(blob, doc.fileName);
}

function downloadAudioItem(recId) {
  const item = state.recordings.find((r) => r.id === recId);
  if (!item || !item.blob) return;
  downloadBlob(item.blob, item.fileName);
}

function triggerAIRun() {
  const project = state.projects.find((p) => p.name === state.selectedProjectName);
  const item = state.recordings.find((r) => r.id === state.selectedAudioIdForAI);
  if (!project || !item) return;
  runAIOperation(item, project, state.selectedAIMode);
}

function triggerStatusAutoUpdate() {
  const project = state.projects.find((p) => p.name === state.selectedProjectName);
  const item = state.recordings.find((r) => r.id === state.selectedAudioIdForAI);
  if (!project || !item) return;
  const docId = `${project.name}__${item.id}__meeting_minutes`;
  const doc = state.documents.find((d) => d.id === docId);
  if (!doc) return;
  autoUpdateProjectStatus(project, doc.content);
}

function render() {
  const tr = t();
  const headerSelect = document.getElementById('headerLangSelect');
  if (headerSelect) {
    headerSelect.innerHTML = APP_LANGUAGES.map(
      (l) => `<option value="${l.code}" ${state.appLang === l.code ? 'selected' : ''}>${l.label}</option>`
    ).join('');
    headerSelect.onchange = (e) => setAppLang(e.target.value);
  }

  const mainEl = document.getElementById('mainContent');
  if (mainEl) {
    if (state.activeTab === 'record') mainEl.innerHTML = renderRecorderTab();
    else if (state.activeTab === 'triage') mainEl.innerHTML = renderTriageTab();
    else if (state.activeTab === 'projects') mainEl.innerHTML = renderProjectsTab();
    else mainEl.innerHTML = renderSettingsTab();
  }

  const unassignedCount = unassignedRecordings().length;
  const tabBarEl = document.getElementById('bottomTabBar');
  if (tabBarEl) {
    tabBarEl.innerHTML = `
      <button class="tab-btn ${state.activeTab === 'record' ? 'active' : ''}" onclick="switchTab('record')">
        <span class="icon">🔴</span>
        <span>${escapeHtml(tr.tabRecord)}</span>
      </button>
      <button class="tab-btn ${state.activeTab === 'triage' ? 'active' : ''}" onclick="switchTab('triage')">
        <span class="icon">📥</span>
        <span>${escapeHtml(tr.tabTriage)}</span>
        ${unassignedCount > 0 ? `<span class="tab-badge">${unassignedCount}</span>` : ''}
      </button>
      <button class="tab-btn ${state.activeTab === 'projects' ? 'active' : ''}" onclick="switchTab('projects')">
        <span class="icon">📁</span>
        <span>${escapeHtml(tr.tabProjects)}</span>
      </button>
      <button class="tab-btn ${state.activeTab === 'settings' ? 'active' : ''}" onclick="switchTab('settings')">
        <span class="icon">⚙️</span>
        <span>${escapeHtml(tr.tabSettings)}</span>
      </button>
    `;
  }
}

// ==================== Bootstrap ====================
window.addEventListener('DOMContentLoaded', async () => {
  if ('serviceWorker' in navigator) {
    navigator.serviceWorker.register('./sw.js').catch(() => {});
  }
  db = await openDatabase();
  await reloadAllData();
});

