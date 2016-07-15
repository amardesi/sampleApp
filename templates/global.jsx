// Header present on almost every page
class Header extends React.Component 
{
  render() { return(
    <div className="header">
      <img src="/images/escholarship_small.png" alt="eScholarship logo" width="170" height="51"/>
      <hr />
    </div>
  )}
}

// Footer present on almost every page
class Footer extends React.Component 
{
  render() { return(
    <div className="footer">
      <hr />
      <img alt="CDL logo" id="cdl_logo" src="/images/CDL_logo_footer.png" width="32" height="32" />
      <span>
        Powered by <a href="http://cdlib.org">California Digital Library</a>
      </span>
    </div>
  )}
}