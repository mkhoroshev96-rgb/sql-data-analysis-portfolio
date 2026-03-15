-- 782. «Ефект прискорення»

WITH level1 as(SELECT customer_id
       ,order_id
	   ,order_date
	   ,SUM(unit_price * quantity * (1-discount)) as sum_chek
	   ,COUNT(order_id) OVER (partition by customer_id) as count_order
	   ,COUNT(order_id) OVER (partition by customer_id) /2 as middle_point
	   ,ROW_NUMBER () OVER (partition by customer_id order by order_date) as rn
FROM orders
JOIN order_details USING (order_id)
GROUP By customer_id, order_id, order_date),
level2 as(SELECT *
       ,case when rn <= middle_point THEN 'first'
	   when rn > middle_point THEN 'second'
	   END as halfs
FROM level1
WHERE count_order >= 10),
level3 as(SELECT customer_id
       ,AVG(sum_chek) FILTER (WHERE halfs = 'first') as avg_chek_first
	   ,AVG(sum_chek) FILTER (WHERE halfs = 'second') as avg_chek_second
FROm level2
GROUP BY customer_id),
level4 as(SELECT *
       ,avg_chek_second / avg_chek_first as momentum_index
FROm level3)
SELECT *
       ,case when momentum_index > 1.1 THEN 'high'
	   when momentum_index between 0.9 AND 1.1 THEN 'normal'
	   when momentum_index < 0.9 THEN 'low'
	   END as gradation
FROm level4
ORDER BY momentum_index DESC

-- 783. «Токсична монетизація»

WITH level1 as(SELECT customer_id
       ,order_id
	   ,order_date
	   ,MAX(discount) as max_discount
	   ,SUM(unit_price * quantity * (1-discount)) as sum_chek
	   ,COUNT(order_id) OVER (partition by customer_id) as count_order
FROM orders
JOIN order_details USING (order_id)
GROUP By customer_id, order_id, order_date),
level2 as(SELECT *
       ,case when max_discount > 0 THEN 'discounted'
	   else 'not_discounted' END as gradation
	   ,SUM(sum_chek) OVER (partition by customer_id) as total_revenue
FROM level1
WHERE count_order >= 8),
level3 as(SELECT *
       ,SUM(sum_chek) OVER (partition by customer_id) as total_revenue_discounted 
FROm level2
WHERE gradation = 'discounted'),
level4 as(SELECT *
       ,total_revenue_discounted / total_revenue as ratio
FROm level3),
level5 as(SELECT DISTINCT customer_id
       ,ratio
FROm level4)
SELECT *
       ,case when ratio < 0.2 THEN 'low'
	   when ratio between 0.2 AND 0.8 THEN 'normal'
	   when ratio > 0.8 THEN 'high'
	   END as classification
FROM level5
ORDER BY ratio DESC

-- 784. «Залежність від топ-продукту»

WITH level1 as(SELECT customer_id
       ,order_id
	   ,order_date
	   ,product_id
	   ,(unit_price * quantity * (1-discount)) as chek
FROm orders
JOIN order_details USING (order_id)),
level2 as(SELECT *
       ,SUM(chek) OVER (partition by customer_id) as total_revenue
	   ,SUM(chek) OVER (partition by customer_id, product_id) as revenue_per_product
FROm level1),
level3 as(SELECT DISTINCT customer_id
	   ,product_id
	   ,revenue_per_product
	   ,total_revenue
FROm level2),
level4 as(SELECT *
       ,MAX(revenue_per_product) OVER (partition by customer_id) as max_revenue_product
FROm level3),
level5 as(SELECT *
       ,max_revenue_product / total_revenue as ratio
FROM level4),
level6 as(SELECT DISTINCT customer_id
       ,max_revenue_product
	   ,total_revenue
	   ,ratio
FROM level5),
level7 as(SELECT customer_id
       ,COUNT(order_id) as count_order
FROM orders
GROUP By customer_id)
SELECT *
       ,case when ratio < 0.2 THEN 'low'
	   when ratio between 0.2 AND 0.8 THEN 'normal'
	   when ratio > 0.8 THEN 'high'
	   END as gradation
FROM level6
JOIN level7 USING (customer_id)
WHERE count_order >= 8
ORDER BY ratio DESC

-- 785. «Ілюзія стабільного клієнта»

WITH level1 as(SELECT customer_id
       ,order_id
	   ,order_date
	   ,SUM(unit_price * quantity * (1-discount)) as sum_chek
	   ,COUNT(order_id) OVER (partition by customer_id) as count_order
	   ,ROW_NUMBER () OVER (partition by customer_id order by order_date DESC, order_id DESC) as rn_invert
FROM orders
JOIN order_details USING (order_id)
GROUP By customer_id, order_id, order_date),
level2 as(SELECT *
       ,ROUND((count_order * 0.33)::numeric,0) as third_count
	   ,SUM(sum_chek) OVER (partition by customer_id) as total_revenue
FROM level1
WHERE count_order >= 9),
level3 as(SELECT *
       ,SUM(sum_chek) FILTER (WHERE rn_invert <= third_count) OVER (partition by customer_id) as revenue_last_third
FROM level2),
level4 as(SELECT *
       ,revenue_last_third / total_revenue as ratio
FROM level3),
level5 as(SELECT DISTINCT customer_id
       ,revenue_last_third
	   ,total_revenue
	   ,ratio
FROm level4)
SELECT *
       ,case when ratio > 0.5 THEN 'high'
	   when ratio < 0.3 THEN 'low'
	   when ratio between 0.3 AND 0.5 THEN 'normal'
	   END as gradation
FROm level5
ORDER BY ratio DESC

-- 786. «Промо-канібалізація»

WITh level1 as(SELECT customer_id
       ,AVG(unit_price) FILTER (WHERE discount > 0) as avg_price_discounted
	   ,AVG(unit_price) FILTER (WHERE discount = 0) as avg_price_not_discounted
	   ,COUNT(DISTINCT order_id) as count_order
FROm orders
JOIN order_details USING (order_id)
GROUP By customer_id)
SELECT customer_id
       ,avg_price_discounted / avg_price_not_discounted as pci
FROm level1
WHERE count_order >= 8 AND avg_price_discounted is not null
AND avg_price_not_discounted is not null
ORDER BY pci DESC

-- 787. Unit Economics клієнтів — чи окупаємо ми їх

WITH level1 as(SELECT customer_id
       ,order_id
	   ,order_date
	   ,SUM(unit_price * quantity * (1-discount)) as sum_chek
	   ,AVG(freight) as freight_per_order
	   ,COUNT(order_id) OVER (partition by customer_id) as count_order
FROm orders
JOIN order_details USING (order_id)
GROUP By customer_id, order_id, order_date),
level2 as(SELECT *
       ,AVG(sum_chek) OVER (partition by customer_id) as avg_chek
	   ,AVG(freight_per_order) OVER(partition by customer_id) as avg_freight_customer
	   ,SUM(sum_chek) OVER (partition by customer_id) as ltv
FROm level1
WHERE count_order >= 5)
SELECT *
FROm level2
WHERE ltv < 500