// Page content for item view
//
// Note: automatically has access to all Components defined in global.jsx, such as
// <Header>, <Footer>, etc.
//
class ItemPage extends React.Component {
  constructor(props) {
    super(props)
    this.state = {currentTab: props.currentTab}
  }

  changeTab(tab_id) {
    this.setState({currentTab: tab_id})
  }

  render() { 
    let p = this.props
    let debugStyle = { backgroundColor: '#dcdcdc' }
    return(
      <div className="container-fluid">
        <Header/>
        <div style={debugStyle}>
          <h2>Item: {p.id}</h2>
          Info:
          <ul>
            <li>Rights: {p.rights}</li>
          </ul>
        </div>
        <p>Breadcrumb and other journal specific header content here</p>
        <div className="row">
          <div className="col-sm-8">
            <ItemTabbed
              {...p}
              currentTab={this.state.currentTab}  // overwrite props.currentTab
              changeTab={this.changeTab.bind(this)}
            />
          </div>
          <div className="col-sm-4">
            <ItemLinkColumn 
              changeTab={this.changeTab.bind(this)}
              {...p}
            />
          </div>
        </div>
        <Footer/>
      </div>
    )
  }
}

{/* Tabbed Navigation courtesy Trey Piepmeier http://codepen.io/trey/post/tabbed-navigation-react*/}
class ItemTabbed extends React.Component {
  constructor(props) {
    super(props)
    this.state = {
      tabList: [ 
        { 'id': 1, 'name': 'Main content', 'url': '#main' },
        { 'id': 2, 'name': 'Data & media', 'url': '#suppl' },
        { 'id': 3, 'name': 'Metrics', 'url': '#metrics' },
        { 'id': 4, 'name': 'Author & article info', 'url': '#authorarticle' },
        { 'id': 5, 'name': 'Comments', 'url': '#comments' } ]
    }
  }

  render() {
    return(
    <div>
      <Tabs
        currentTab={this.props.currentTab}
        tabList={this.state.tabList}
        changeTab={this.props.changeTab}
      />
      <ContentSwitch {...this.props}/>
    </div>
  )}
}

class Tabs extends React.Component {
  handleClick(tab){
    this.props.changeTab(tab.id)
  }
  
  render() { return(
    <ul className="nav nav-tabs">
    {this.props.tabList.map(function(tab) {
      return (
        <Tab
          handleClick={this.handleClick.bind(this, tab)}
          key={tab.id}
          url={tab.url}
          name={tab.name}
          isCurrent={(this.props.currentTab === tab.id)}
         />
      )
    }.bind(this))}
    </ul>
  )}
}

class Tab extends React.Component {
  handleClick(e){
    e.preventDefault()
    this.props.handleClick()
  }
  
  render() { 
    return(
    <li className="nav-item">
      <a className={this.props.isCurrent ? 'current' : null} 
         onClick={this.handleClick.bind(this)}
         href={this.props.url}>{this.props.name}&nbsp;&nbsp;
      </a>
    </li>
  )}
}

class ContentSwitch extends React.Component {
  render() {
    return(
    <div>
      {this.props.currentTab === 1 ? <ContentMain {...this.props}/> : null }
      {this.props.currentTab === 2 ? <ContentSuppl {...this.props}/> : null}
      {this.props.currentTab === 3 ? <ContentMetrics {...this.props}/> : null}
      {this.props.currentTab === 4 ? <ContentAuthArt {...this.props}/> : null}
      {this.props.currentTab === 5 ? <ContentComments {...this.props}/> : null}
    </div>
  )}
}

/* Put these somewhere else and import in to make this all a bit cleaner */
class ContentMain extends React.Component {
  render() { 
    let p = this.props
    return(
      <div className="content">
        {p.title} <br/>
        {p.pub_date}
      </div>
    )
  }
}

class ContentSuppl extends React.Component {
  render() { 
    let p = this.props
    return(
      <div className="content">
        Data &amp; Media content here
      </div>
    )
  }
}

class ContentMetrics extends React.Component {
  render() { 
    let p = this.props
    return(
      <div className="content">
        Metrics content here
      </div>
    )
  }
}

class ContentAuthArt extends React.Component {
  render() { 
    let p = this.props
    return(
      <div className="content">
        Author &amp; Article content here
      </div>
    )
  }
}

class ContentComments extends React.Component {
  render() { 
    let p = this.props
    return(
      <div className="content">
        Comments content here
      </div>
    )
  }
}

class ItemLinkColumn extends React.Component {
  handleClick(tab_id) {  
    this.props.changeTab(tab_id)
  }

  render() { 
    let p = this.props
    return(
      <div>
        <div className="card card-block">
          <h4 className="card-title">Download</h4>
          Article: PDF | ePub | HTML<br/>
          Image<br/>
          Media<br/>
          <a href="#"
             onClick={this.handleClick.bind(this, 2)}
             className="card-link">
            more...
          </a>
        </div> 
        <div className="card card-block">
          <h4 className="card-title">Buy</h4>
          <a href="#" className="card-link">Link</a>
        </div> 
        <div className="card card-block">
          <h4 className="card-title">Share</h4>
          <a href="#" className="card-link">Link</a>
        </div>
        <div className="card card-block">
          <h4 className="card-title">Jump to:</h4>
          <a href="#" className="card-link">Link</a>
        </div>
        <div className="card card-block">
          <h4 className="card-title">Related Items</h4>
          <a href="#" className="card-link">Link</a>
        </div>
      </div>
    )
  }
}
/* Put those (above) somewhere else and import in to make this all a bit cleaner */

// Render everything under the single top-level div created in the base HTML. As its
// initial properties, pass it the chunk of initialData included in the base HTML.
ReactDOM.render(<ItemPage currentTab="1" {...initialData}/>, document.getElementById('uiBase'))
