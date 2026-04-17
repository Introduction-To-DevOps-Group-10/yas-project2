package com.yas.search.repository;

import com.yas.search.model.Product;
import org.springframework.context.annotation.Lazy;
import org.springframework.data.elasticsearch.repository.ElasticsearchRepository;
import org.springframework.stereotype.Repository;

@Repository
@Lazy
public interface ProductRepository extends ElasticsearchRepository<Product, Long> {
}
