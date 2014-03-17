require 'spec_helper'
require 'fileutils'

describe Sly::Interface do
  let!(:api) { Sly::Interface.new }

  describe '.api_term' do
    before do
      stub_const("Sly::API_DICTIONARY", { "foo" => "bar" })
    end

    context "value exists in dictionary" do
      it "returns the key" do
        Sly::Interface.api_term("bar").should == "foo"
      end
    end

    context "value not in dictionary" do
      it "returns the search value" do
        Sly::Interface.api_term("baz").should == "baz"
      end
    end
  end

  describe '.common_term' do
    before do
      stub_const("Sly::API_DICTIONARY", { "foo" => "bar" })
    end

    context "key exists in dictionary" do
      it "returns the key" do
        Sly::Interface.common_term("foo").should == "bar"
      end
    end

    context "key not in dictionary" do
      it "returns the search value" do
        Sly::Interface.common_term("baz").should == "baz"
      end
    end
  end

  describe '.new_if_config' do
    context "config file exists" do
      before { Sly::Interface.stub(:new) }

      it "returns a new interface" do
        Sly::Interface.new_if_config.should == Sly::Interface.new
      end
    end

    context "no config file" do
      before do
        Sly::Interface.stub(:new).and_raise(Sly::ConfigFileMissingError)
      end

      it "outputs the error" do
        capture_stdout do
          begin
            Sly::Interface.new_if_config
          rescue SystemExit
          end
        end.should include("ERROR: Config File Missing")
      end

      it "exits" do
        lambda { Sly::Interface.new_if_config }.should raise_error(SystemExit)
      end
    end
  end

  describe '#cache' do
    let!(:products) { fixture("products.json") }

    it "creates a cache directory if one does not exist" do
      FileUtils.rm_rf(Sly::CACHE_DIR) if FileTest::directory?(Sly::CACHE_DIR)
      FileTest::directory?(Sly::CACHE_DIR).should be_false

      api.cache("products.json") { products }

      FileTest::directory?(Sly::CACHE_DIR).should be_true
    end

    it "creates a cache file if one does not exist" do
      cache_file = "#{Sly::CACHE_DIR}/products.json"
      File.delete(cache_file) if File.exists?(cache_file)

      api.cache("products.json") { products }

      File.exists?(cache_file).should be_true
    end
  end

  describe '#add_item' do
    let(:attributes) { { id: 1, title: "My Item" } }
    let(:item) { double(:item, to_flat_hash: attributes) }

    it "calls the api with the item attributes" do
      api.connector.should_receive(:add_item).with(attributes)
      api.add_item(item)
    end
  end

  describe '#update_item' do
    let(:id) { 1 }
    let(:item) do
      {
        type: "task",
        number: id,
        score: "S",
        tags: "tag1,tag2"
      }
    end

    before do
      api.connector.stub(:item).with(id).and_return(item)
    end

    it "only updates valid attributes" do
      api.connector.should_receive(:update_item).with(id, {
        number: id,
        score: "M",
        tags: "tag1,tag2"
      })
      api.update_item(id, {
        score: "M",
        not_item_attribute: true,
      })
    end

    it "does not try to update the type" do
      api.connector.should_receive(:update_item).with(id, {
        number: id,
        score: "S",
        tags: "tag1,tag2"
      })
      api.update_item(id, {
        type: "story"
      })
    end

    it "flattens tag updates" do
      api.connector.should_receive(:update_item).with(id, {
        number: id,
        score: "S",
        tags: "tagA,tagB"
      })
      api.update_item(id, {
        tags: ["tagA", "tagB"]
      })
    end
  end

  describe '#people' do
    context "api success" do
      before { api.stub(cache: json_fixture("people")) }

      it "returns a list of people" do
        api.people.first.should be_a_kind_of(Sly::Person)
      end

      it "sorts by name" do
        api.people.map(&:last_name).should == ["Rayner", "White", "Wroblewski"]
      end

      context "filtering by assigned user" do
        it "returns people with names that contain the query" do
          api.people("ray").map(&:last_name).should == ["Rayner"]
        end

        it "filters by 'me'" do
          api.connector.config.email = "test1@example.com"
          api.people("me").map(&:last_name).should == ["Wroblewski"]
        end
      end
    end

    context "api error" do
      before do
        api.stub(:cache)
        api.stub(error_object?: true)
      end

      it "returns an empty list" do
        api.people.should == []
      end
    end
  end

  describe '#products' do
    context "api success" do
      before { api.stub(cache: json_fixture("products")) }

      it "returns a list of products" do
        api.products.first.should be_a_kind_of(Sly::Product)
      end

      it "returns products with names that start with the query" do
        api.products("alice").map(&:name).should == ["Alice Product"]
      end
    end

    context "api error" do
      before do
        api.stub(:cache)
        api.stub(error_object?: true)
      end

      it "returns an empty list" do
        api.products.should == []
      end
    end
  end

  describe '#items' do
    context "api success" do
      before { api.stub(cache: json_fixture("items")) }

      it "returns a list of items" do
        api.items.first.should be_a_kind_of(Sly::Item)
      end

      it "rejects orphaned items" do
        api.items.map(&:number).should_not include(666)
      end

      context "filtering by assigned user" do
        it "returns items whose assignee name contains the query" do
          api.items({}, "@dom").map(&:number).should == [111,444]
        end

        it "returns items whose assignee is 'me'" do
          api.connector.config.email = "test1@example.com"
          api.items({}, "@me").map(&:number).should == [111,444]
        end
      end

      it "filters by title" do
        api.items({}, "item 1").map(&:number).should == [111]
      end
    end

    context "api error" do
      before do
        api.stub(:cache)
        api.stub(error_object?: true)
      end

      it "returns an empty list" do
        api.products.should == []
      end
    end
  end

  describe '#product' do
    let(:id) { 1111 }
    let(:product) { Hash.new }

    before do
      api.connector.stub(:product).with(id).and_return(product)
    end

    it "converts response to a typed object" do
      Sly::Product.should_receive(:new).with(product)
      api.product(id)
    end

    it "returns the typed object" do
      api.product(id).should be_a_kind_of(Sly::Product)
    end

    context "api error" do
      before { api.stub(error_object?: true) }

      it "returns nil" do
        api.product(id).should == nil
      end
    end
  end

  describe '#person' do
    let(:id) { 1111 }
    let(:person) { Hash.new }

    before do
      api.connector.stub(:person).with(id).and_return(person)
    end

    it "converts response to a typed object" do
      Sly::Person.should_receive(:new).with(person)
      api.person(id)
    end

    it "returns the typed object" do
      api.person(id).should be_a_kind_of(Sly::Person)
    end

    context "api error" do
      before { api.stub(error_object?: true) }

      it "returns nil" do
        api.person(id).should == nil
      end
    end
  end

  describe '#item' do
    let(:id) { 1111 }
    let(:item) { Hash.new }

    before do
      api.connector.stub(:item).with(id).and_return(item)
    end

    it "converts response to a typed object" do
      Sly::Item.should_receive(:new_typed).with(item)
      api.item(id)
    end

    it "returns the typed object" do
      api.item(id).should be_a_kind_of(Sly::Item)
    end

    context "api error" do
      before { api.stub(error_object?: true) }

      it "returns nil" do
        api.item(id).should == nil
      end
    end
  end

  describe '#error_object?' do
    it "returns false for a list response" do
      api.send(:error_object?, json_fixture("products")).should be_false
    end

    it "returns false for a single response" do
      api.send(:error_object?, json_fixture("item")).should be_false
    end

    it "returns true for an error response" do
      api.send(:error_object?, json_fixture("403")).should be_true
    end
  end
end
