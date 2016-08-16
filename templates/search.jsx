var facetData = [
  {id: 1, fieldsetLabel: "Refine By", fieldName: "refineBy", inputItems: [
    {id: 1, value: "peer-reviewed", label: "Peer-reviewed only (##)"}
  ]},
  {id: 2, fieldsetLabel: "Research", fieldName: "research", inputItems: [
    {id: 2, value: "articles", label: "Articles (##)"}, 
    {id: 3, value: "books", label: "Books (##)"}, 
    {id: 4, value: "theses", label: "Theses (##)"}
  ]},
  {id: 3, fieldsetLabel: "Content Type", fieldName: "contentType", inputItems: [
    {id: 5, value: "video", label: "Video"}, 
    {id: 6, value: "audio", label: "Audio"}, 
    {id: 7, value: "images", label: "Images"}, 
    {id: 8, value: "pdf", label: "PDF"}, 
    {id: 9, value: "zip", label: "ZIP"}
  ]},
  //assumption: when display === "range", then inputItems.length === 2, inputItems[0] is start, and inputItems[1] is end
  {id: 4, fieldsetLabel: "Publication Year", fieldName: "publicationYear", display: "range", inputItems: [
    {id: 10, value: "start", label: "From:", fieldType: "text"}, 
    {id: 11, value: "end", label: "To:", fieldType: "text"}
  ]},
  {id: 5, fieldsetLabel: "Campuses", fieldName: "campuses", inputItems: [
    {id: 12, value: "ucb", label: "UC Berkeley"},
    {id: 13, value: "ucd", label: "UC Davis"},
    {id: 14, value: "uci", label: "UC Irvine"},
  ]},
  {id: 6, fieldsetLabel: "Departments", fieldName: "departments", display: "hierarchy", inputItems: [
    {id: 15, value: "ahc", label: "Agricultural History Center"}, 
    {id: 16, value: "ag-nat-resources-research-ext-centers", label: "Agriculture and Natural Resources Research and Extension Centers", inputItems: [
      {id: 17, value: "hop-research-extension-center", label: "Hopland Research and Extension Center"},
      {id: 18, value: "sierra-foothill-reasearch-and-extension-center", label: "Sierra Foothill Research and Extension Center"}
    ]},
    {id: 19, value: "american-cultures-center", label: "American Cultures Center"}
  ]},
  {id: 7, fieldsetLabel: "Journals", fieldName: "journals"},
  {id: 8, fieldsetLabel: "Disciplines", fieldName: "disciplines"},
  {id: 9, fieldsetLabel: "Reuse License", fieldName: "reuseLicense"},
]

class CurrentSearchTerms extends React.Component {
  render() {
    return (
      <div className="currentSearchTerms">
        <h3>Search</h3>
        <a href="#">clear all</a>
        <p>Results: 12,023 items</p>
        <p>You searched for: 'open acces' and refined by: Research (Articles) <a href="#">x</a> Publication Year (all) <a href="#">x</a> Campuses (Berkeley) <a href="#">x</a></p>
        <a href="#">less</a>
      </div>
    )
  }
}

class FacetItem extends React.Component {
  render() {
    return (
      <div className="facetItem">
        <label htmlFor={this.props.value}>{this.props.label}</label>
        <input id={this.props.value} className="facet" type="checkbox" value={this.props.label}/>
      </div>
    );
  }
}

class FacetRange extends React.Component {
  render() {
    return (
      <div className="facetRange">
        <label htmlFor={this.props.start.value}>{this.props.start.label}</label>
        <input id={this.props.start.value} className="facet" type="text" />
        <label htmlFor={this.props.end.value}>{this.props.end.label}</label>
        <input id={this.props.end.value} className="facet" type="text" />
      </div>
    );
  }
}

class FacetHierarchy extends React.Component {
  render() {
    var childrenNodes;
    if (this.props.inputItems !== undefined) {
      childrenNodes = this.props.inputItems.map(function(input) {
        return (
          <FacetItem key={input.id} value={input.value} label={input.label} inputItems={input.inputItems} />
        );
      });
    }
    return (
      <div className="facetHierarchy">
        <label htmlFor={this.props.value}>{this.props.label}</label>
        <input id={this.props.value} className="facet" type="checkbox" value={this.props.label}/>
        <div className="facetHierarchyChildren" style={{paddingLeft: "20px"}}>
          {childrenNodes}
        </div>
      </div>
    );
  }
}

class FacetFieldset extends React.Component {
  showFacetItems(e) {
    $(e.currentTarget).siblings('.facetItems').slideToggle();
  }

  render() {
    var facetItemNodes;
    if (this.props.data.inputItems !== undefined) {
      if (this.props.data.display === "range") {
        facetItemNodes = (<FacetRange start={this.props.data.inputItems[0]} end={this.props.data.inputItems[1]} />)
      } else if (this.props.data.display === "hierarchy") {
        facetItemNodes = this.props.data.inputItems.map(function(input) {
          return (
            <FacetHierarchy key={input.id} value={input.value} label={input.label} inputItems={input.inputItems} />
          );
        });
      } else {
        facetItemNodes = this.props.data.inputItems.map(function(input) {
          return (
            <FacetItem key={input.id} value={input.value} label={input.label} />
          );
        });        
      }
    }
    
    return (
      <fieldset className="facetFieldset {this.props.data.fieldName}">
        <legend onClick={this.showFacetItems}>{this.props.data.fieldsetLabel}</legend>
        <div className="facetItems" style={{display: 'none'}}>
          {facetItemNodes}
        </div>
      </fieldset>
    );
  }
}

class FacetForm extends React.Component {
  render() {
    return (
      <form className="facetForm">
        {this.props.data.map(function(facetfieldset) {
          return <FacetFieldset key={facetfieldset.id} data={facetfieldset} />
        })}
      </form>
    );
  }
}

class SearchResultsSidebar extends React.Component {
  render() {
    return (
      <div className="searchResultSidebar col-xs-3">
        <CurrentSearchTerms />
        <FacetForm data={this.props.data} />
      </div>
    );
  }
}

class Pagination extends React.Component {
  render() {
    return (
      <div className="pagination">
        lalala pagination goes here!
      </div>
    );
  }
}

class ViewOptions extends React.Component {
  render() {
    return (
      <div className="viewOptions row">
        <label htmlFor="sort">Sort By:</label>
        <select id="sort"><option>Relevance</option></select>
        <label htmlFor="rows">Per Page:</label>
        <select id="rows"><option>10</option></select>
        <Pagination />
      </div>
    );
  }
}

class InformationResultsSet extends React.Component {
  render() {
    return (  
      <div className="informationResultsSet">
        <h2>Information</h2>
        <p>Article 1</p>
        <p>Article 2</p>
        <p>Article 3</p>
        <a>Show more >></a>
      </div>
    );
  }
}

class ResearchResultsSet extends React.Component {
  render() {
    return (  
      <div className="researchResultsSet">
        <h2>Research</h2>
        <p>Article 1</p>
        <p>Article 2</p>
        <p>Article 3</p>
        <p>Article 4</p>
        <p>Article 5</p>
        <p>Article 6</p>
        <p>Article 7</p>
        <p>Article 8</p>
        <p>Article 9</p>
        <p>Article 10</p>
        <Pagination />
      </div>
    );
  }
}

class SearchResultsSet extends React.Component {
  render() {
    return (
      <div className="searchResultsSet col-xs-9">
        <ViewOptions />
        <InformationResultsSet />
        <ResearchResultsSet />      
      </div>
    );
  }
}

class SearchResults extends React.Component {
  render() {
    return (
      <div className="searchResults">
        <SearchResultsSidebar data={this.props.data} />
        <SearchResultsSet/>
      </div>
    );
  }
}

ReactDOM.render(
  <SearchResults data={facetData} />,
  document.getElementById('uiBase')
);