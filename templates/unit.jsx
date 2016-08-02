// Page content for unit landing page.
//
// Note: automatically has access to all Components defined in global.jsx, such as
// <Header>, <Footer>, etc.
//
class UnitPage extends React.Component
{
  render() { 
    let p = this.props
    return(
      <div className="container-fluid">
        <Header/>
        <h2>{p.id}</h2>
        <div>
          Info:
          <ul>
            <li>Name: {p.name}</li>
            <li>Type: {p.type}</li>
          </ul>
        </div>
        <div>
          Parents:
          <ul>
            { p.parents.map((parent_id) => 
              <li key={parent_id}><a href={"/unit/"+parent_id}>{parent_id}</a></li>) }
          </ul>
        </div>
        <div>
          Children:
          <ul>
            { p.children.map((child_id) => 
              <li key={child_id}><a href={"/unit/"+child_id}>{child_id}</a></li>) }
          </ul>
        </div>
        { p.items.length==0 ? null :
            <div>
              Items 1-{Math.min(10, p.nItems)} of {p.nItems}:
              <ul>
                { p.items.map((item_id) => 
                  <li key={item_id}><a href={"/item/"+item_id.replace(/^qt/, "")}>{item_id}</a></li>) }
              </ul>
            </div>
        }
        <Footer/>
      </div>
    )
  }
}

// Render everything under the single top-level div created in the base HTML. As its
// initial properties, pass it the chunk of initialData included in the base HTML.
ReactDOM.render(<UnitPage {...initialData}/>, document.getElementById('uiBase'))
