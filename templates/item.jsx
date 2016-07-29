// Page content for item view
//
// Note: automatically has access to all Components defined in global.jsx, such as
// <Header>, <Footer>, etc.
//
class ItemPage extends React.Component
{
  render() { 
    let p = this.props
    return(
      <div className="container-fluid">
        <Header/>
        <h2>Item: {p.id}</h2>
        <div>
          Info:
          <ul>
            <li>Title: {p.title}</li>
          </ul>
          {/* Andy hack here */}
        </div>
        <Footer/>
      </div>
    )
  }
}

// Render everything under the single top-level div created in the base HTML. As its
// initial properties, pass it the chunk of initialData included in the base HTML.
ReactDOM.render(<ItemPage {...initialData}/>, document.getElementById('uiBase'))
