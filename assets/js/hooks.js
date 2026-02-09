let Hooks = {}

Hooks.MentionInput = {
  mounted() {
    const pushCursor = () => {
      const pos = this.el.selectionStart
      this.pushEvent("cursor_position", { position: pos })
    }
    this.el.addEventListener("input", pushCursor)
    this.el.addEventListener("keyup", pushCursor)
    this.el.addEventListener("click", pushCursor)
  },
  handleEvent("set_ask_input_value", (payload) => {
    const value = payload && payload.value
    if (this.el && typeof value === "string") {
      this.el.value = value
      this.pushEvent("update_input", { text: value })
    }
  })
}

Hooks.SelectContactWithText = {
  mounted() {
    this.el.addEventListener("click", (e) => {
      const btn = e.target.closest("[data-contact-id]")
      if (!btn) return
      e.preventDefault()
      e.stopPropagation()
      const textarea = document.getElementById("ask-message-input")
      const text = textarea ? textarea.value : ""
      this.pushEvent("select_contact", {
        id: btn.dataset.contactId,
        name: btn.dataset.contactName || btn.dataset.contactId,
        provider: btn.dataset.contactProvider,
        text: text
      })
    })
  }
}

Hooks.Clipboard = {
    mounted() {
        this.handleEvent("copy-to-clipboard", ({ text: text }) => {
            navigator.clipboard.writeText(text).then(() => {
                this.pushEventTo(this.el, "copied-to-clipboard", { text: text })
                setTimeout(() => {
                    this.pushEventTo(this.el, "reset-copied", {})
                }, 2000)
            })
        })
    }
}

export default Hooks