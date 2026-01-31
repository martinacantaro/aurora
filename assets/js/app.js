// If you want to use Phoenix channels, run `mix help phx.gen.channel`
// to get started and then uncomment the line below.
// import "./user_socket.js"

// You can include dependencies in two ways.
//
// The simplest option is to put them in assets/vendor and
// import them using relative paths:
//
//     import "../vendor/some-package.js"
//
// Alternatively, you can `npm install some-package --prefix assets` and import
// them using a path starting with the package name:
//
//     import "some-package"
//
// If you have dependencies that try to import CSS, esbuild will generate a separate `app.css` file.
// To load it, simply add a second `<link>` to your `root.html.heex` file.

// Include phoenix_html to handle method=PUT/DELETE in forms and buttons.
import "phoenix_html"
// Establish Phoenix Socket and LiveView configuration.
import {Socket} from "phoenix"
import {LiveSocket} from "phoenix_live_view"
import {hooks as colocatedHooks} from "phoenix-colocated/aurora"
import topbar from "../vendor/topbar"
import Sortable from "sortablejs"

// Custom hooks
const Hooks = {
  // Voice input hook using Web Speech API
  VoiceInput: {
    mounted() {
      // Check for browser support
      const SpeechRecognition = window.SpeechRecognition || window.webkitSpeechRecognition
      if (!SpeechRecognition) {
        console.warn("Speech recognition not supported in this browser")
        this.el.style.display = "none"
        return
      }

      this.recognition = new SpeechRecognition()
      this.recognition.continuous = false
      this.recognition.interimResults = true
      this.recognition.lang = "en-US"
      this.isListening = false

      // Find the input field
      this.inputField = document.querySelector('input[name="message"]')

      this.recognition.onstart = () => {
        this.isListening = true
        this.el.classList.add("btn-error", "animate-pulse")
        this.el.classList.remove("btn-imperial")
        this.pushEvent("voice_recording_started", {})
      }

      this.recognition.onend = () => {
        this.isListening = false
        this.el.classList.remove("btn-error", "animate-pulse")
        this.el.classList.add("btn-imperial")
        this.pushEvent("voice_recording_stopped", {})
      }

      this.recognition.onresult = (event) => {
        let finalTranscript = ""
        let interimTranscript = ""

        for (let i = event.resultIndex; i < event.results.length; i++) {
          const transcript = event.results[i][0].transcript
          if (event.results[i].isFinal) {
            finalTranscript += transcript
          } else {
            interimTranscript += transcript
          }
        }

        // Update input field with interim results for visual feedback
        if (this.inputField) {
          this.inputField.value = finalTranscript || interimTranscript
        }

        // When we have a final result, send it
        if (finalTranscript) {
          this.pushEvent("voice_input", { text: finalTranscript.trim() })
        }
      }

      this.recognition.onerror = (event) => {
        console.error("Speech recognition error:", event.error)
        this.isListening = false
        this.el.classList.remove("btn-error", "animate-pulse")
        this.el.classList.add("btn-imperial")

        if (event.error === "not-allowed") {
          alert("Microphone access denied. Please allow microphone access to use voice input.")
        }
      }

      // Toggle recording on click
      this.el.addEventListener("click", () => {
        if (this.isListening) {
          this.recognition.stop()
        } else {
          this.recognition.start()
        }
      })
    },

    destroyed() {
      if (this.recognition && this.isListening) {
        this.recognition.stop()
      }
    }
  },

  // Scroll to bottom hook for chat messages
  ScrollToBottom: {
    mounted() {
      this.scrollToBottom()
      this.observer = new MutationObserver(() => this.scrollToBottom())
      this.observer.observe(this.el, { childList: true, subtree: true })
    },
    updated() {
      this.scrollToBottom()
    },
    destroyed() {
      if (this.observer) {
        this.observer.disconnect()
      }
    },
    scrollToBottom() {
      this.el.scrollTop = this.el.scrollHeight
    }
  },
  // Sortable hook for drag-and-drop
  Sortable: {
    mounted() {
      const group = this.el.dataset.group

      this.sortable = new Sortable(this.el, {
        group: group,
        animation: 150,
        ghostClass: "opacity-50",
        dragClass: "shadow-lg",
        draggable: "[data-id]",
        onEnd: (evt) => {
          // Only handle on the source element to avoid duplicate events
          if (this.el !== evt.from) return

          if (group === "columns") {
            // Reorder columns
            const ids = Array.from(evt.from.parentElement.children)
              .filter(el => el.dataset.id)
              .map(el => parseInt(el.dataset.id))
            this.pushEvent("reorder_columns", { ids })
          } else if (group === "tasks") {
            const taskId = evt.item.dataset.id
            const toColumnId = evt.to.dataset.columnId
            const newPosition = evt.newIndex

            if (evt.from === evt.to) {
              // Reorder within same column
              const ids = Array.from(evt.to.children)
                .filter(el => el.dataset.id)
                .map(el => parseInt(el.dataset.id))
              this.pushEvent("reorder_tasks", { column_id: toColumnId, ids })
            } else {
              // Move to different column
              this.pushEvent("move_task", {
                task_id: taskId,
                column_id: toColumnId,
                position: newPosition
              })
            }
          } else if (group === "schedule") {
            const taskId = evt.item.dataset.taskId
            const toDate = evt.to.dataset.date
            const toHour = evt.to.dataset.hour
            const isUnscheduledContainer = evt.to.id === "unscheduled-tasks"

            if (isUnscheduledContainer) {
              // Dropped on unscheduled sidebar - unschedule the task
              this.pushEvent("unschedule_task", { task_id: taskId })
            } else if (toDate && toHour) {
              // Dropped on a time slot - schedule the task
              this.pushEvent("schedule_task", {
                task_id: taskId,
                date: toDate,
                hour: toHour
              })
            }
          }
        }
      })
    },
    destroyed() {
      if (this.sortable) {
        this.sortable.destroy()
      }
    }
  }
}

const csrfToken = document.querySelector("meta[name='csrf-token']").getAttribute("content")
const liveSocket = new LiveSocket("/live", Socket, {
  longPollFallbackMs: 2500,
  params: {_csrf_token: csrfToken},
  hooks: {...colocatedHooks, ...Hooks},
})

// Show progress bar on live navigation and form submits
topbar.config({barColors: {0: "#29d"}, shadowColor: "rgba(0, 0, 0, .3)"})
window.addEventListener("phx:page-loading-start", _info => topbar.show(300))
window.addEventListener("phx:page-loading-stop", _info => topbar.hide())

// connect if there are any LiveViews on the page
liveSocket.connect()

// expose liveSocket on window for web console debug logs and latency simulation:
// >> liveSocket.enableDebug()
// >> liveSocket.enableLatencySim(1000)  // enabled for duration of browser session
// >> liveSocket.disableLatencySim()
window.liveSocket = liveSocket

// The lines below enable quality of life phoenix_live_reload
// development features:
//
//     1. stream server logs to the browser console
//     2. click on elements to jump to their definitions in your code editor
//
if (process.env.NODE_ENV === "development") {
  window.addEventListener("phx:live_reload:attached", ({detail: reloader}) => {
    // Enable server log streaming to client.
    // Disable with reloader.disableServerLogs()
    reloader.enableServerLogs()

    // Open configured PLUG_EDITOR at file:line of the clicked element's HEEx component
    //
    //   * click with "c" key pressed to open at caller location
    //   * click with "d" key pressed to open at function component definition location
    let keyDown
    window.addEventListener("keydown", e => keyDown = e.key)
    window.addEventListener("keyup", _e => keyDown = null)
    window.addEventListener("click", e => {
      if(keyDown === "c"){
        e.preventDefault()
        e.stopImmediatePropagation()
        reloader.openEditorAtCaller(e.target)
      } else if(keyDown === "d"){
        e.preventDefault()
        e.stopImmediatePropagation()
        reloader.openEditorAtDef(e.target)
      }
    }, true)

    window.liveReloader = reloader
  })
}

