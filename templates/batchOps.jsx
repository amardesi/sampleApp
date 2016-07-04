class AsyncStatus extends React.Component
{
  render() { 
    let p = this.props
    if (p.error)
      return(<p><b>Fatal Error:</b> {p.error}</p>)
    return(
      <p>
        {p.operation}<br/>
        {p.percentDone ?
          <progress className="progress" value={p.percentDone} max="100" style={{width: "50%"}}>
            {p.percentDone}%
          </progress> : ""}
      </p>)
  }
}

class NoteList extends React.Component
{
  render() { 
    let p = this.props
    return(
      <div key={"notes-"+p.name}>
        <div><b>{p.name + (p.notes.length > 1 ? "s" : "")}</b></div>
        <ul>
          { p.notes.map((note, idx) => <li key={idx}>{note}</li>) }
        </ul>
      </div>
    )
  }
}

class ExportSection extends React.Component
{
  constructor(props) {
    super(props)
    this.state = { status: null, notes: {} }
  }

  render() { 
    let p = this.props, s = this.state
    return(
      <div name="exportSection">
        <p>
          <b>Series export for {p.entity}:</b>&nbsp;
          <button onClick={()=>this.startExport()}>Metadata</button>
          &nbsp;|&nbsp;
          <a href="exportContent">Content</a>
        </p>
        { (s.status) ? <AsyncStatus {...s.status}/> : "" }
        { (s.notes.dataErrors)   ? <NoteList name="Error"   notes={s.notes.dataErrors}  /> : "" }
        { (s.notes.dataWarnings) ? <NoteList name="Note"    notes={s.notes.dataWarnings}/> : "" }
      </div>
    )
  }

  startExport() 
  {
    let ws = new WebSocket(
      window.location.href.replace(/^http/, 'ws').replace(/batchOps.*/, "exportAsync?entity=" + this.props.entity))
    this.setState({ status: { operation: 'Exporting', percentDone: 0 }, notes: {} }) // blow away prev notes
    ws.onmessage = (msg)=>{
      /*console.log('websocket message: ' +  m.data)*/
      let data = JSON.parse(msg.data)
      if (data.appendNote) {
        let newNotes = _.clone(this.state.notes)
        _.each(data.appendNote, (value, key) => {
          if (!(key in newNotes))
            newNotes[key] = []
          newNotes[key].push(value)
        })
        this.setState({ notes: newNotes })
      }
      else {
        this.setState(data)
        if ("downloadURL" in data.status)
          window.location = data.status.downloadURL
        if (data.status.error || data.status.downloadURL)
          ws.close()
      }
    }
  }
}

class ImportSection extends React.Component
{
  constructor(props) {
    super(props)
    this.state = { status: null, notes: {}, mode: "idle" }
  }

  render() { 
    let p = this.props, s = this.state
    return(
      <div name="importSection">
        <p>
          <b>Series import for {p.entity}:</b>&nbsp;
          <input type="file" ref="metaImportFile" onChange={(evt)=>this.startImport(evt.target.files[0])}/>
          { /*(s.status && s.mode == "idle") ? <button name="redo" onClick={()=>this.startImport(this.refs.metaImportFile.files[0])}>Redo</button> : ""*/ }
          { s.socket ? <button name="cancel" onClick={()=>this.cancelOperation()}>Cancel</button> : "" }
        </p>

        { (s.status) ? <AsyncStatus {...s.status}/> : "" }
        { (s.status2) ? <AsyncStatus {...s.status2}/> : "" }

        { (s.notes.dataErrors)   ? <NoteList name="Error"   notes={s.notes.dataErrors}  /> : "" }
        { (s.notes.dataWarnings) ? <NoteList name="Note"    notes={s.notes.dataWarnings}/> : "" }
        { (s.notes.dataDiffs)    ? <NoteList name="Diff"    notes={s.notes.dataDiffs}   /> : "" }
        { (s.notes.dataSummary)  ? <NoteList name="Summary" notes={s.notes.dataSummary}   /> : "" }

        { (s.notes.dataSummary && !s.notes.dataErrors) ? <button name="process" onClick={()=>this.startProcessing()}>Process all</button> : "" }
      </div>
    )
  }

  startImport(file) 
  {
    if (!file) { return }
    this.setState({ status: { operation: 'Uploading:', percentDone: 0 }, notes: {}, mode: "running" }) // blow away prev notes
    let fd = new FormData()
    fd.append("metaImportFile", file)
    let xhr = new XMLHttpRequest()
    xhr.upload.addEventListener("progress", (evt)=>this.importProgress(evt), false)
    xhr.addEventListener("load", (evt)=>this.importComplete(evt), false)
    xhr.addEventListener("error", (evt)=>this.importError(evt), false)
    xhr.addEventListener("abort", (evt)=>this.importError(evt), false)
    xhr.open("POST", "importAsync?entity=" + this.props.entity)
    xhr.send(fd)
  }

  importProgress(evt) {
    this.setState({ status: { 
      operation: 'Uploading:', 
      percentDone: evt.lengthComputable ? Math.round(evt.loaded * 100 / evt.total) : 50 
    } })
  }

  importComplete(evt) {
    if (evt.target.status != 200) return this.importError(evt)
    this.setState({ status: { operation: 'Upload complete', percentDone: 100 } })
    // Reset the file input element
    var $el = $(this.refs.metaImportFile)
    $el.wrap('<form>').closest('form').get(0).reset()
    $el.unwrap()
    // And begin checking
    this.startCheck()
  }

  importError(evt) {
    let t = evt.target
    this.setState({ status: { error: "Upload failed: " + t.responseText ? t.responseText : t.statusText }, mode: "idle" })
  }

  startCheck() 
  {
    let ws = new WebSocket(window.location.href.replace(/^http/, 'ws').replace(/batchOps.*/, "checkAsync?entity=" + this.props.entity))
    this.setState({ status: { operation: 'Checking: 0%', percentDone: 0 }, socket: ws, notes: {} })
    ws.onmessage = (msg)=>{
      //console.log('message during checking:', msg.data)
      let data = JSON.parse(msg.data)
      if (data.appendNote) {
        let newNotes = _.clone(this.state.notes)
        _.each(data.appendNote, (value, key) => {
          if (!(key in newNotes))
            newNotes[key] = []
          newNotes[key].push(value)
        })
        this.setState({ notes: newNotes })
      }
      else {
        this.setState(data)
        if (data.status.error || data.status.percentDone == 100)
          ws.close()
      }
    }
    ws.onclose = (msg)=>{
      this.setState({ mode: "idle", socket: null })
    }
  }

  cancelOperation() {
    this.state.socket.send("cancel")
  }

  startProcessing() 
  {
    let ws = new WebSocket(window.location.href.replace(/^http/, 'ws').replace(/batchOps.*/, "processAsync?entity=" + this.props.entity))
    this.setState({ status: { operation: 'Processing: 0%', percentDone: 0 }, socket: ws, notes: {} })
    ws.onmessage = (msg)=>{
      //console.log('message during processing:', msg.data)
      let data = JSON.parse(msg.data)
      if (data.appendNote) {
        let newNotes = _.clone(this.state.notes)
        _.each(data.appendNote, (value, key) => {
          if (!(key in newNotes))
            newNotes[key] = []
          newNotes[key].push(value)
        })
        this.setState({ notes: newNotes })
      }
      else {
        this.setState(data)
        if (data.status.error || data.status.percentDone == 100)
          ws.close()
      }
    }
    ws.onclose = (msg)=>{
      this.setState({ mode: "idle", socket: null })
    }
  }
}

// Page content for batch operations
class BatchOpsPage extends React.Component
{
  render() { 
    return(
    <div className="container-fluid">
      <br/>
      <ExportSection entity={this.props.entity}/>
      <hr/>
      <ImportSection entity={this.props.entity}/>
      <br/>
    </div>
  )}
}

// Render everything under the single top-level div created in the base HTML
ReactDOM.render(<BatchOpsPage {...initialData}/>, document.getElementById('uiBase'))
