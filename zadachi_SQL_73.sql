-- 461. «Знижка без користі» (парадокс “більше → не краще”)

WITH level1 as(SELECT customer_id
       ,order_id
	   ,order_date
	   ,ROUND(AVG(discount)::numeric,4) as avg_discount
	   ,ROUND(AVG(unit_price)::numeric,2) as avg_price
	   ,COUNT(order_id) OVER (partition by customer_id) as count_order
FROM orders
JOIN order_details USING (order_id)
GROUP BY customer_id, order_id, order_date),
level2 as(SELECT *
       ,LAG(avg_discount) OVER (partition by customer_id order by order_date) as prev_discount
	   ,LAG(avg_price) OVER (partition by customer_id order by order_date) as prev_price
FROM level1
WHERE count_order >= 3)
SELECT *
FROM level2
WHERE avg_discount > prev_discount AND avg_price < prev_price
AND avg_price * (1 - avg_discount) >= prev_price * (1-prev_discount)

-- 462. «Замовлення-бутафорія»

WITh level1 as(SELECT customer_id
       ,order_id
	   ,order_date
	   ,SUM(quantity) as sum_quantity
	   ,COUNT(order_id) OVER (partition by customer_id) as count_order
FROM orders
JOIN order_details USING (order_id)
GROUP By customer_id, order_id, order_date),
level2 as(SELECT *
       ,LAG(sum_quantity) OVER (partition by customer_id order by order_date) as prev_quantity
	   ,LEAD(sum_quantity) OVER (partition by customer_id order by order_date) as next_quantity
FROM level1
WHERE count_order >= 3),
level3 as(SELECT *
       ,case when sum_quantity > prev_quantity AND next_quantity <= prev_quantity THEN 'yes'
	   ELSE 'no' END as flag_quantity
	   ,(prev_quantity + next_quantity) / 2 as avg_prev_next
FROM level2)
SELECT *
FROM level3
WHERE avg_prev_next is not null AND avg_prev_next >= sum_quantity 
AND flag_quantity = 'yes'

-- 463. «Клієнт із фальшивим зростанням»

WITH level1 as(SELECT customer_id
       ,order_id
	   ,order_date
	   ,SUM(quantity) as sum_quantity
	   ,COUNT(order_id) OVER (partition by customer_id) as count_order
FROM orders
JOIN order_details USING (order_id)
GROUP BY customer_id, order_id, order_date),
level2 as(SELECT *
       ,LAG(sum_quantity) OVER (partition by customer_id order by order_date) as prev_quantity
	   ,LEAD(sum_quantity) OVER (partition by customer_id order by order_date) as next_quantity
FROM level1
WHERE count_order >= 5),
level3 as(SELECT *
       ,case when sum_quantity > prev_quantity AND next_quantity <= prev_quantity THEN 1
	   ELSE 0 END as flag_quantity
FROM level2),
level4 as(SELECT *
       ,SUM(flag_quantity) OVER (partition by customer_id) as sum_flag_quantity
FROM level3),
level5 as(SELECT *
       ,ROW_NUMBER() OVER (partition by customer_id order by order_date) as rn
	   ,ROW_NUMBER() OVER (partition by customer_id order by order_date DESC) as rn_invert
FROm level4
WHERE sum_flag_quantity >= 2),
level6 as(SELECT customer_id
       ,ROUND(AVG(sum_quantity) FILTER (WHERE rn = 1)::numeric,2) as quantity_first
	   ,ROUND(AVG(sum_quantity) FILTER (WHERE rn_invert = 1)::numeric,2) as quantity_last
FROM level5
GROUP BY customer_id),
level7 as(SELECT *
       ,COUNT(order_id) OVER (partition by customer_id) as real_count
	   ,COUNT(order_id) OVER (partition by customer_id) / 2 as middle_point
	   ,ROW_NUMBER() OVER (partition by customer_id order by order_date) as ranks
FROM level5
JOIN level6 USING (customer_id)
WHERE quantity_last > quantity_first),
level8 as(SELECT *
FROM level7
WHERE flag_quantity = 0),
level9 as(SELECT *
       ,case when ranks <= middle_point THEN 'first'
	   when ranks > middle_point THEN 'second'
	   END as halfs
FROM level8),
level10 as(SELECT customer_id
       ,halfs
	   ,percentile_cont(0.5) WITHIN GROUP (order by sum_quantity) as median
FROM level9
GROUP BY customer_id, halfs),
level11 as(SELECT *
       ,AVG(median) FILTER (WHERE halfs = 'first') OVER (partition by customer_id) as median_first
	   ,AVG(median) FILTER (WHERE halfs = 'second') OVER (partition by customer_id) as median_second
FROM level9
JOIN level10 USING (customer_id, halfs))
SELECT *
FROM level11
WHERE median_second <= median_first

-- 464. «Клієнт із зламаною реакцією»

WITH level1 as(SELECT customer_id
       ,order_id
	   ,order_date
	   ,SUM(quantity) as sum_quantity
	   ,COUNT(order_id) OVER (partition by customer_id) as count_order
FROm orders
JOIn order_details USING (order_id)
GROUP By customer_id, order_id, order_date),
level2 as(SELECT *
       ,LAG(sum_quantity) OVER (partition by customer_id order by order_date) as prev_quantity
	   ,LEAD(sum_quantity) OVER (partition by customer_id order by order_date) as next_quantity
FROM level1
WHERE count_order >= 4),
level3 as(SELECT *
       ,case when sum_quantity > prev_quantity THEN 1 ELSE 0 END as stymul
FROM level2),
level4 as(SELECT *
       ,SUM(stymul) OVER (partition by customer_id) as sum_stymul
FROM level3),
level5 as(SELECT *
FROM level4
WHERE sum_stymul >= 1),
level6 as(SELECT *
       ,case when next_quantity >= prev_quantity THEN 0 ELSE 1 END as flag_zlam
FROM level5
WHERE stymul = 1),
level7 as(SELECT *
       ,SUM(flag_zlam) OVER (partition by customer_id) as sum_flag_zlam
	   ,COUNT(order_id) OVER (partition by customer_id) as real_count
FROM level6
WHERE prev_quantity is not null AND next_quantity is not null)
SELECT *
FROM level7
WHERE sum_flag_zlam = real_count

-- 465. Найтоповіший клієнт

WITH level1 as(SELECT customer_id
       ,order_id
	   ,ROUND(AVG(unit_price)::numeric,2) as avg_price_order
	   ,ROUND(AVG(discount)::numeric,4) as avg_discount_order
	   ,SUM(quantity) as sum_quantity_order
	   ,ROUND(SUM(unit_price * quantity * (1-discount))::numeric,2) as sum_chek
	   ,COUNT(order_id) OVER (partition by customer_id) as count_order
FROM orders
JOIN order_details USING (order_id)
GROUP BY customer_id, order_id),
level2 as(SELECT customer_id
       ,ROUND(AVG(avg_price_order)::numeric,2) as avg_price
	   ,ROUND(AVG(avg_discount_order)::numeric,4) as avg_discount
	   ,SUM(sum_quantity_order) as total_quantity
	   ,SUM(sum_chek) as total_revenue
	   ,ROUND(AVG(count_order)::numeric,0) as count_order_per_customer
FROM level1
GROUP By customer_id),
level3 as(SELECT *
       ,DENSE_RANK () OVER (order by avg_price DESC) as rank_price
	   ,DENSE_RANK () OVER (order by avg_discount DESC) as rank_discount
	   ,DENSE_RANK () OVER (order by total_quantity DESC) as rank_quantity
	   ,DENSE_RANK () OVER (order by total_revenue DESC) as rank_chek
	   ,DENSE_RANK () OVER (order by count_order_per_customer DESC) as rank_count
FROM level2),
level4 as(SELECT *
       ,ROUND(((rank_price + rank_discount + rank_quantity + rank_chek + rank_count)::numeric / 5),2) as total_rank
FROM level3)
SELECT *
FROM level4
ORDER BY total_rank
LIMIT 5 

-- 466. «Найтоповіший, якого не видно»

WITH level1 as(SELECT customer_id
       ,order_id
	   ,ROUND(SUM(unit_price * quantity * (1-discount))::numeric,2) as sum_chek
	   ,COUNT(order_id) OVER (partition by customer_id) as count_order
FROM orders
JOIN order_details USING (order_id)
GROUP BY customer_id, order_id),
level2 as(SELECT customer_id
       ,SUM(sum_chek) as total_revenue
	   ,ROUND(AVG(count_order)::numeric,0) as orders_per_customer
FROM level1
WHERE count_order >= 5
GROUP By customer_id),
level3 as(SELECT *
       ,ROUND((total_revenue / orders_per_customer)::numeric,2) as avg_chek_per_order
FROM level2),
level4 as(SELECT *
       ,DENSE_RANK () OVER (order by total_revenue DESC) as rank_revenue
	   ,DENSE_RANK () OVER (order by orders_per_customer DESC) as rank_count
	   ,DENSE_RANK () OVER (order by avg_chek_per_order DESC) as rank_chek_per_order
FROM level3)
SELECT *
FROM level4
WHERE rank_revenue <= 5 AND rank_count > 20 AND rank_chek_per_order <= 3

-- 467. «Клієнт, який зіпсував середнє»

WITH level1 as(SELECT customer_id
       ,order_id
	   ,ROUND(SUM(unit_price * quantity * (1-discount))::numeric,2) as sum_chek
	   ,COUNT(order_id) OVER (partition by customer_id) as count_order
FROM orders
JOIN order_details USING (order_id)
GROUP By customer_id, order_id),
level2 as(SELECT customer_id
       ,SUM(sum_chek) as total_revenue
	   ,ROUND(AVG(count_order)::numeric,2) as counts
FROM level1
WHERE count_order >= 5
GROUP BY customer_id),
level3 as(SELECT *
       ,ROUND((total_revenue / counts)::numeric,2) as revenue_per_order
FROM level2),
level4 as(SELECT *
       ,ROUND(AVG(revenue_per_order) OVER ()::numeric,2) as global_avg_per_order
	   ,DENSE_RANK () OVER (order by total_revenue DESC) as rank_revenue
	   ,DENSE_RANK () OVER (order by revenue_per_order DESC) as rank_avg_revenue
FROM level3),
level5 as(SELECT *
       ,SUM(revenue_per_order) OVER () as global_sum_per_order
	   ,COUNT(customer_id) OVER () as total_count
FROM level4),
level6 as(SELECT *
       ,ROUND((global_sum_per_order - revenue_per_order) / (total_count - 1)::numeric,2) as avg_ohne_customer
FROM level5)
SELECT *
FROM level6
WHERE global_avg_per_order > avg_ohne_customer AND rank_revenue > 3 AND rank_avg_revenue > 3
