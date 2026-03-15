-- 248. “Категорії з ілюзією прибутковості”

WITH level1 as(SELECT category_id
       ,order_id
	   ,ROUND(SUM(p.unit_price * quantity * (1-discount))::numeric,2) as sum_chek
	   ,COUNT(*) OVER (partition by category_id) as count_order
FROM orders
JOIN order_details USING(order_id)
JOIN products p USING (product_id)
JOIN categories USING(category_id)
GROUP BY category_id, order_id),
level2 as(SELECT DISTINCT category_id
	   ,SUM(sum_chek) OVER (partition by category_id) as total_revenue
	   ,ROUND((SUM(sum_chek) OVER (partition by category_id) / count_order)::numeric,2) as profit_per_order
FROM level1
WHERE count_order > 50),
level3 as(SELECT *
       ,ROUND(AVG(total_revenue) OVER ()::numeric,2) as global_avg_total_revenue
	   ,ROUND(AVG(profit_per_order) OVER () :: numeric,2) as global_profit_per_order
FROM level2)
SELECT *
FROM level3
WHERE total_revenue > global_avg_total_revenue AND profit_per_order < global_profit_per_order

-- 249. “Клієнти з ефектом «фальстарту»”

WITH level1 as(SELECT customer_id
       ,order_id
	   ,order_date
	   ,ROUND(SUM(unit_price * quantity * (1-discount))::numeric,2) as sum_chek
	   ,COUNT(*) OVER (partition by customer_id) as count_order
FROM orders
JOIn order_details USING(order_id)
GROUP BY customer_id, order_id, order_date),
level2 as(SELECT *
       ,dense_rank() OVER (partition by customer_id order by order_date) as rank_date 
FROM level1
WHERE count_order >= 2),
level3 as(SELECT customer_id
       ,ROUND(percentile_cont(0.5) WITHIN GROUP (order by sum_chek)::numeric,2) as median_chek
FROM level1
GROUP BY customer_id),
level4 as(SELECT *
FROM level2
JOIn level3 USING(customer_id)),
level5 as(SELECT *
       ,LEAD(sum_chek) OVER (partition by customer_id order by order_date) as second_chek
FROM level4),
level6 as(SELECT *
       ,case when sum_chek > median_chek AND sum_chek > second_chek THEN 'yes_of_cours' 
	   ELSE 'no' END as gradation
FROM level5
WHERE rank_date = 1)
SELECT *
FROM level6
WHERE gradation = 'yes_of_cours'

-- 250. “Клієнти з ефектом відкладеного розчарування”

WITH level1 as(SELECT customer_id
       ,order_id
	   ,order_date
	   ,ROUND(SUM(unit_price * quantity * (1-discount))::numeric,2) as sum_chek
	   ,COUNT(order_id) OVER (partition by customer_id) as count_order
FROM orders
JOIN order_details USING(order_id)
GROUP By customer_id, order_id, order_date),
level2 as(SELECT *
       ,ROUND(AVG(sum_chek) OVER (partition by customer_id)::numeric,2) as avg_sum_chek
	   ,dense_rank() OVER (partition by customer_id order by order_date) as rank_date
	   ,LEAD(sum_chek) OVER (partition by customer_id order by order_date) as second_chek
FROm level1
WHERE count_order >=5),
level3 as(SELECT *
       ,LEAD(second_chek) OVER (partition by customer_id order by order_date) as third_chek
	   ,MIN(sum_chek) OVER (partition by customer_id) as min_chek
FROM level2),
level4 as(SELECT *
FROM level3
WHERE rank_date = 1 AND third_chek <> min_chek),
level5 as(SELECT *
       ,case when sum_chek > avg_sum_chek AND second_chek > avg_sum_chek AND third_chek < avg_sum_chek THEN 'yes'
	   ELSE 'no' END as gradation
FROM level4)
SELECT *
FROM level5
WHERE gradation = 'yes'

-- 251. “Клієнти з ефектом хибного відновлення”

WITH level1 as(SELECT customer_id
       ,order_id
	   ,order_date
	   ,ROUND(SUM(unit_price * quantity * (1-discount))::numeric,2) as sum_chek
	   ,COUNT(order_id) OVER (partition by customer_id) as count_order
FROm orders
JOIN order_details USING(order_id)
GROUP BY customer_id,order_id, order_date),
level2 as(SELECT *
       ,ROUND(AVG(sum_chek) OVER (partition by customer_id)::numeric,2) as avg_chek_per_customer
       ,DENSE_rank() OVER (partition by customer_id order by order_date) as rank_date
	   ,LEAD(sum_chek) OVER (partition by customer_id order by order_date) as second_chek
FROM level1),
level3 as(SELECT *
       ,LEAD(second_chek) OVER (partition by customer_id order by order_date) as third_chek
FROM level2
WHERE count_order >= 6),
level4 as(SELECT *
       ,case when second_chek < sum_chek AND third_chek > second_chek AND third_chek < avg_chek_per_customer THEN 'yes'
	   ELSE 'no' END as gradation
FROM level3
WHERE second_chek is not null AND third_chek is not null)
SELECT *
FROM level4
WHERE gradation = 'yes'

-- 252. “Клієнти з розбалансованою ціною”

WITH level1 as(SELECT customer_id
       ,order_id
	   ,order_date
	   ,ROUND(AVG(unit_price * (1-discount))::numeric,2) as avg_price_after_discount
	   ,ROUND(SUM(unit_price * quantity * (1-discount))::numeric,2) as sum_chek
	   ,COUNT(order_id) OVER (partition by customer_id) as count_order
FROM orders
JOIn order_details USING(order_id)
GROUP BY customer_id,order_id,order_date),
level2 as(SELECT *
       ,DENSE_RANK() OVER (partition by customer_id order by order_date) as rank_date
	   ,LEAD(avg_price_after_discount) OVER (partition by customer_id order by order_date) as second_price
	   ,LEAD(sum_chek) OVER (partition by customer_id order by order_date) as second_chek
FROM level1
WHERE count_order >= 4),
level3 as(SELECT *
       ,LEAD(second_price) OVER (partition by customer_id order by order_date) as third_price
	   ,LEAD(second_chek) OVER (partition by customer_id order by order_date) as third_chek
FROm level2),
level4 as(SELECT *
       ,case when avg_price_after_discount < second_price AND second_price < third_price THEN 'yes' ELSE 'no' END flag_price
	   ,case when sum_chek >= second_chek AND second_chek >= third_chek THEN 'yes' ELSE 'no' END flag_chek
FROm level3
WHERE third_chek is not null AND third_price is not null)
SELECT *
FROM level4
WHERE flag_chek = 'yes' AND flag_price = 'yes'