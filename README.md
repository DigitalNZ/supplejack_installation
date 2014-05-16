Supplejack Rails Application Template
===================

Supplejack is a platform for managing the harvesting and manipulation of metadata. It was originally developed to manage the sourcing of metadata for the [DigitalNZ](http://digitalnz.org) aggregation service, and has grown to a platform that can manage millions of records from hundreds of data sources.

It's main purpose is to manage the process of fetching data from remote sources, mappaing data to a standard data schema, managing any quality control or enrichment processes, and surfacing the standardised data via a public API. The full Supplejack code repo is on GitHub.

This is a [Rails Application Template](http://guides.rubyonrails.org/rails_application_templates.html) for installing the Supplejack Stack.

For a full list of dependancies and documentation please refer to http://digitalnz.github.io/supplejack/

## Usage

To install the Supplejack stack run the following command:

```bash
rails _3.2.12_ new mysupplejack_api_name --skip-bundle -m https://raw.github.com/digitalnz/supplejack_template/master/supplejack_api_template.rb
```

## COPYRIGHT AND LICENSING  

### SUPPLEJACK CODE - GNU GENERAL PUBLIC LICENCE, VERSION 3  

Supplejack, a tool for aggregating, searching and sharing metadata records, is Crown copyright (C) 2014, New Zealand Government. 

Supplejack was created by DigitalNZ at the National Library of NZ and the Department of Internal Affairs. http://digitalnz.org/supplejack  

This program is free software: you can redistribute it and/or modify it under the terms of the GNU General Public License as published by the Free Software Foundation, either version 3 of the License, or (at your option) any later version.   This program is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the GNU General Public License for more details.  You should have received a copy of the GNU General Public License along with this program. If not, see http://www.gnu.org/licenses / http://www.gnu.org/licenses/gpl-3.0.txt 
