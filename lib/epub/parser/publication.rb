require 'nokogiri'
require 'addressable/uri'
require 'epub/publication'
require 'epub/constants'

module EPUB
  class Parser
    class Publication
      class << self
        def parse(file)
          new(file).parse
        end
      end

      def initialize(file)
        @package = EPUB::Publication::Package.new
        @rootfile = Addressable::URI.parse File.realpath(file)
        @doc = Nokogiri.XML open(file)
      end

      def parse
        parse_package
        parse_metadata
        parse_manifest
        parse_spine
        parse_guide
        # parse_bindings

        @package
      end

      def parse_package
        elem = @doc.root
        @package.version = elem['version']
        @package.unique_identifier_id = elem['unique-identifier']

        @package
      end

      def parse_metadata
        metadata = @package.metadata = EPUB::Publication::Package::Metadata.new
        elem = @doc.xpath('/opf:package/opf:metadata', EPUB::NAMESPACES).first
        id_map = {}

        metadata.identifiers = elem.xpath('./dc:identifier', EPUB::NAMESPACES).collect do |e|
          identifier = EPUB::Publication::Package::Metadata::Identifier.new
          identifier.content = e.content
          identifier.id = id = e['id']
          metadata.unique_identifier = identifier if id == @package.unique_identifier_id

          identifier
        end
        metadata.identifiers.each {|i| id_map[i.id] = {metadata: i} if i.id}

        metadata.titles = collect_dcmes(elem, './dc:title') do |title, e|
          title.content = e.content
        end
        metadata.titles.each {|t| id_map[t.id] = {metadata: t} if t.id}

        metadata.languages = elem.xpath('./dc:language', EPUB::NAMESPACES).collect do |e|
          e.content
        end
        metadata.languages.each {|l| id_map[l.id] = {metadata: l} if l.respond_to?(:id) && l.id}

        %w[ contributor coverage creator date description format publisher relation source subject type ].each do |dcmes|
          metadata.__send__ "#{dcmes}s=", collect_dcmes(elem, "./dc:#{dcmes}")
          metadata.__send__("#{dcmes}s").each {|d| id_map[d.id] = {metadata: d} if d.respond_to?(:id) && d.id}
        end

        metadata.rights = collect_dcmes(elem, './dc:rights')
        metadata.rights.each {|r| id_map[r.id] = {metadata: r} if r.respond_to?(:id) && r.id}

        metadata.metas = elem.xpath('./opf:meta', EPUB::NAMESPACES).collect do |e|
          # parse meta, link to Item and then return meta itself
          meta = EPUB::Publication::Package::Metadata::Meta.new
          %w[ property id scheme ].each { |attr| meta.__send__("#{attr}=", e[attr]) }
          meta.content = e.content
          if (refines = e['refines']) && refines[0] == '#'
            id = refines[1..-1]
            id_map[id] ||= {}
            id_map[id][:metas] ||= []
            id_map[id][:metas] << meta
          end

          meta
        end
        metadata.metas.each {|m| id_map[m.id] = {metadata: m} if m.respond_to?(:id) && m.id}

        metadata.links = elem.xpath('./opf:link', EPUB::NAMESPACES).collect do |e|
          EPUB::Publication::Package::Metadata::Link.new
        end
        metadata.links.each {|l| id_map[l.id] = {metadata: l} if l.respond_to?(:id) && l.id}

        id_map.values.each do |hsh|
          next unless hsh[:metas]
          next unless hsh[:metadata]
          hsh[:metadata].refiners = hsh[:metas]
          hsh[:metas].each {|meta| meta.refines = hsh[:metadata]}
        end

        metadata
      end

      def parse_manifest
        manifest = @package.manifest = EPUB::Publication::Package::Manifest.new
        elem = @doc.xpath('/opf:package/opf:manifest', EPUB::NAMESPACES).first
        manifest.id = elem['id']

        fallback_map = {}
        elem.xpath('./opf:item', EPUB::NAMESPACES).each do |e|
          item = EPUB::Publication::Package::Manifest::Item.new
          %w[ id media-type media-overlay ].each do |attr|
            item.__send__("#{attr.gsub(/-/, '_')}=", e[attr])
          end
          item.href = e['href']
          item.iri = @rootfile.join Addressable::URI.parse(e['href'])
          fallback_map[e['fallback']] = item if e['fallback']
          item.properties = e['properties'] ? e['properties'].split(' ') : []
          manifest << item
        end
        fallback_map.each_pair do |id, from|
          from.fallback = manifest[id]
        end

        manifest
      end

      def parse_spine
        spine = @package.spine = EPUB::Publication::Package::Spine.new
        elem = @doc.xpath('/opf:package/opf:spine', EPUB::NAMESPACES).first
        %w[ id toc page-progression-direction ].each do |attr|
          spine.__send__("#{attr.gsub(/-/, '_')}=", elem[attr])
        end

        elem.xpath('./opf:itemref', EPUB::NAMESPACES).each do |e|
          itemref = EPUB::Publication::Package::Spine::Itemref.new
          %w[ idref id ].each do |attr|
            itemref.__send__("#{attr}=", e[attr])
          end
          itemref.linear = (e['linear'] != 'no')
          itemref.properties = e['properties'] ? e['properties'].split(' ') : []
          spine << itemref
        end

        spine
      end

      def parse_guide
        guide = @package.guide = EPUB::Publication::Package::Guide.new
        elem = @doc.xpath('/opf:package/opf:guide/opf:reference', EPUB::NAMESPACES).each do |ref|
          reference = EPUB::Publication::Package::Guide::Reference.new
          %w[ type title href ].each do |attr|
            reference.__send__("#{attr}=", ref[attr])
          end
          reference.iri = @rootfile.join Addressable::URI.parse(reference.href)
          guide << reference
        end

        guide
      end

      def parse_bindings
        raise 'still not implemented'
      end

      def collect_dcmes(elem, selector)
        elem.xpath(selector, EPUB::NAMESPACES).collect do |e|
          md = EPUB::Publication::Package::Metadata::DCMES.new
          md.content = e.content
          %w[ id lang dir ].each do |attr|
            md.__send__("#{attr}=", e[attr])
          end
          yield(md, e) if block_given?
          md
        end
      end
    end
  end
end
