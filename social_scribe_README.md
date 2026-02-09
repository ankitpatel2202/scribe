# SocialScribe

SocialScribe is a Phoenix + LiveView application that records meetings, generates AI-powered insights, and syncs actionable updates directly into CRMs like **Salesforce** and **HubSpot**. It also provides a chat-based interface for querying CRM data using natural language and contact mentions.

The project focuses on clean architecture, production-ready deployment, and ease of onboarding for future contributors.

---

## ✨ Features

### 🎙 Meeting Recording & Transcription
- Automatically joins Google Meet meetings using Recall.ai
- Captures transcripts and participants
- Stores structured meeting data in Postgres

### 🤖 AI-Powered Insights
- Generates meeting summaries and key takeaways
- Suggests CRM updates based on conversation context

### 🔄 CRM Integrations
- Salesforce and HubSpot OAuth
- Review and sync AI-suggested updates

### 💬 Chat-Based CRM Q&A
- Ask questions with @mentions
- Works across connected CRMs

---

## 🧱 Tech Stack
Elixir, Phoenix, LiveView, PostgreSQL, Oban, Gemini, Recall.ai, Salesforce, HubSpot, Fly.io

---

## 🚀 Live Deployment
https://social-scribe-proud-dust-3503.fly.dev

---

## 🛠 Local Development

```bash
git clone https://github.com/ankitpatel2202/scribe.git
cd social_scribe
mix deps.get
mix ecto.setup
mix phx.server
```

---

## 📦 Deployment (Fly.io)

```bash
fly launch
fly secrets set SECRET_KEY_BASE=...
fly deploy
fly ssh console -C "/app/bin/migrate"
```

---

## 📄 License
Provided as part of a technical challenge.
