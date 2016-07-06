// Page content for unit landing page
class UnitPage extends React.Component
{
  render() { 
    return(
    <div className="container-fluid">
      <Header/>
      <p>Unit</p>
      <Footer/>
    </div>
  )}
}

// Render everything under the single top-level div created in the base HTML
ReactDOM.render(<UnitPage {...initialData}/>, document.getElementById('uiBase'))
